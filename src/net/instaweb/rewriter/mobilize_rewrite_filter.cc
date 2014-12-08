/*
 * Copyright 2014 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Author: stevensr@google.com (Ryan Stevens)

#include "net/instaweb/rewriter/public/mobilize_rewrite_filter.h"

#include <algorithm>

#include "base/logging.h"
#include "net/instaweb/rewriter/public/domain_lawyer.h"
#include "net/instaweb/rewriter/public/request_properties.h"
#include "net/instaweb/rewriter/public/rewrite_driver.h"
#include "net/instaweb/rewriter/public/rewrite_options.h"
#include "net/instaweb/rewriter/public/server_context.h"
#include "net/instaweb/rewriter/public/static_asset_manager.h"
#include "net/instaweb/rewriter/static_asset_config.pb.h"
#include "pagespeed/kernel/base/basictypes.h"
#include "pagespeed/kernel/base/statistics.h"
#include "pagespeed/kernel/base/string.h"
#include "pagespeed/kernel/base/string_util.h"
#include "pagespeed/kernel/html/html_element.h"
#include "pagespeed/kernel/html/html_node.h"
#include "pagespeed/kernel/http/google_url.h"

namespace net_instaweb {

const MobileRoleData MobileRoleData::kMobileRoles[MobileRole::kInvalid] = {
  // This is the order that the HTML content will be rearranged.
  MobileRoleData(MobileRole::kKeeper, "keeper"),
  MobileRoleData(MobileRole::kHeader, "header"),
  MobileRoleData(MobileRole::kNavigational, "navigational"),
  MobileRoleData(MobileRole::kContent, "content"),
  MobileRoleData(MobileRole::kMarginal, "marginal")
};

const char MobilizeRewriteFilter::kPagesMobilized[] =
    "mobilization_pages_rewritten";
const char MobilizeRewriteFilter::kKeeperBlocks[] =
    "mobilization_keeper_blocks_found";
const char MobilizeRewriteFilter::kHeaderBlocks[] =
    "mobilization_header_blocks_found";
const char MobilizeRewriteFilter::kNavigationalBlocks[] =
    "mobilization_navigational_blocks_found";
const char MobilizeRewriteFilter::kContentBlocks[] =
    "mobilization_content_blocks_found";
const char MobilizeRewriteFilter::kMarginalBlocks[] =
    "mobilization_marginal_blocks_found";
const char MobilizeRewriteFilter::kDeletedElements[] =
    "mobilization_elements_deleted";

namespace {

// The 'book' says to use add ",user-scalable=no" but jmarantz hates
// this.  I want to be able to zoom in.  Debate with the writers of
// that book will need to occur.
const char kViewportContent[] = "width=device-width";

const HtmlName::Keyword kPreserveNavTags[] = {HtmlName::kA};
const HtmlName::Keyword kTableTags[] = {
  HtmlName::kCaption, HtmlName::kCol, HtmlName::kColgroup, HtmlName::kTable,
  HtmlName::kTbody, HtmlName::kTd, HtmlName::kTfoot, HtmlName::kTh,
  HtmlName::kThead, HtmlName::kTr};
const HtmlName::Keyword kTableTagsToBr[] = {HtmlName::kTable, HtmlName::kTr};

#ifndef NDEBUG
void CheckKeywordsSorted(const HtmlName::Keyword* list, int len) {
  for (int i = 1; i < len; ++i) {
    DCHECK(list[i - 1] < list[i]);
  }
}
#endif  // #ifndef NDEBUG

}  // namespace

const HtmlName::Keyword MobilizeRewriteFilter::kKeeperTags[] = {
  HtmlName::kArea, HtmlName::kMap, HtmlName::kScript, HtmlName::kStyle};
const int MobilizeRewriteFilter::kNumKeeperTags = arraysize(kKeeperTags);

MobilizeRewriteFilter::MobilizeRewriteFilter(RewriteDriver* rewrite_driver)
    : CommonFilter(rewrite_driver),
      body_element_depth_(0),
      keeper_element_depth_(0),
      reached_reorder_containers_(false),
      added_viewport_(false),
      added_style_(false),
      added_containers_(false),
      added_mob_js_(false),
      added_progress_(false),
      in_script_(false),
      use_js_layout_(rewrite_driver->options()->mob_layout()),
      use_js_logo_(rewrite_driver->options()->mob_logo()),
      use_js_nav_(rewrite_driver->options()->mob_nav()),
      rewrite_js_(rewrite_driver->options()->Enabled(
          RewriteOptions::kRewriteJavascriptExternal)) {
  // If a domain proxy-suffix is specified, and it starts with ".",
  // then we'll remove the "." from that and use that as the location
  // of the shared static files (JS and CSS).  E.g.
  // for a proxy_suffix of ".suffix" we'll look for static files in
  // "//suffix/static/".
  StringPiece suffix(
      rewrite_driver->options()->domain_lawyer()->proxy_suffix());
  if (!suffix.empty() && suffix.starts_with(".")) {
    suffix.remove_prefix(1);
    static_file_prefix_ = StrCat("//", suffix, "/static/");
  }
  Statistics* stats = rewrite_driver->statistics();
  num_pages_mobilized_ = stats->GetVariable(kPagesMobilized);
  num_keeper_blocks_ = stats->GetVariable(kKeeperBlocks);
  num_header_blocks_ = stats->GetVariable(kHeaderBlocks);
  num_navigational_blocks_ = stats->GetVariable(kNavigationalBlocks);
  num_content_blocks_ = stats->GetVariable(kContentBlocks);
  num_marginal_blocks_ = stats->GetVariable(kMarginalBlocks);
  num_elements_deleted_ = stats->GetVariable(kDeletedElements);
#ifndef NDEBUG
  CheckKeywordsSorted(kKeeperTags, kNumKeeperTags);
  CheckKeywordsSorted(kPreserveNavTags, arraysize(kPreserveNavTags));
  CheckKeywordsSorted(kTableTags, arraysize(kTableTags));
  CheckKeywordsSorted(kTableTagsToBr, arraysize(kTableTagsToBr));
#endif  // #ifndef NDEBUG
}

MobilizeRewriteFilter::~MobilizeRewriteFilter() {}

void MobilizeRewriteFilter::InitStats(Statistics* statistics) {
  statistics->AddVariable(kPagesMobilized);
  statistics->AddVariable(kKeeperBlocks);
  statistics->AddVariable(kHeaderBlocks);
  statistics->AddVariable(kNavigationalBlocks);
  statistics->AddVariable(kContentBlocks);
  statistics->AddVariable(kMarginalBlocks);
  statistics->AddVariable(kDeletedElements);
}

void MobilizeRewriteFilter::DetermineEnabled(GoogleString* disabled_reason) {
  // Note: we may need to narrow the set of applicable user agents here, but for
  // now we (very) optimistically assume that our JS works on any mobile UA.
  // TODO(jmaessen): Some debate over whether to include tablet UAs here.  We
  // almost certainly want touch-friendliness, but the geometric constraints are
  // very different and we probably want to turn off almost all non-navigational
  // mobilization.
  // TODO(jmaessen): If we want to inject instrumentation on desktop pages to
  // beacon back data useful for mobile page views, this should change and we'll
  // want to check at code injection points instead.
  if (!driver()->options()->mob_always() &&
      !driver()->request_properties()->IsMobile()) {
    disabled_reason->assign("Not a mobile User Agent.");
    set_is_enabled(false);
  }
}

void MobilizeRewriteFilter::StartDocumentImpl() {
}

void MobilizeRewriteFilter::EndDocument() {
  num_pages_mobilized_->Add(1);
  body_element_depth_ = 0;
  keeper_element_depth_ = 0;
  reached_reorder_containers_ = false;
  added_viewport_ = false;
  added_style_ = false;
  added_containers_ = false;
  added_mob_js_ = false;
  added_progress_ = false;
  in_script_ = false;
}

void MobilizeRewriteFilter::StartElementImpl(HtmlElement* element) {
  HtmlName::Keyword keyword = element->keyword();

  // Unminify jquery for javascript debugging.
  if (keyword == HtmlName::kScript) {
    in_script_ = true;

#if 0
    // Uncomment to translate jquery.min.js to jquery.js for debugging.
    // Alternatively, do this only if this is served from google APIs where
    // we know we have access to both versions.
    HtmlElement::Attribute* src_attribute =
        element->FindAttribute(HtmlName::kSrc);
    if (src_attribute != NULL) {
      StringPiece src(src_attribute->DecodedValueOrNull());
      if (src.find("jquery.min.js") != StringPiece::npos) {
        GoogleString new_value = src.as_string();
        GlobalReplaceSubstring("/jquery.min.js", "/jquery.js", &new_value);
        src_attribute->SetValue(new_value);
      }
    }
#endif
  }
  if (keyword == HtmlName::kMeta) {
    // Remove any existing viewport tags, other than the one we created
    // at start of head.
    StringPiece name(element->EscapedAttributeValue(HtmlName::kName));
    if (name == "viewport") {
      driver()->DeleteNode(element);
      num_elements_deleted_->Add(1);
    }
  } else if (keyword == HtmlName::kHead) {
    // <meta name="viewport"... />
    if (!added_viewport_) {
      added_viewport_ = true;

      if (use_js_layout_) {
        // Transmit to the mobilization scripts whether they are run in debug
        // mode or not by setting 'psDebugMode'.
        GoogleString src = StrCat(
            "var psDebugMode=", driver()->DebugMode() ? "true;" : "false;");
        driver()->InsertScriptAfterCurrent(src, false);
      }

      // TODO(jmarantz): Consider waiting to see if we have a charset directive
      // and move this after that.  This requires some constraints on when
      // flushes occur.  As we sort out our 'flush' strategy we should ensure
      // the charset is declared as early as possible.
      //
      // OTOH convert_meta_tags should make that moot by copying the
      // charset into the HTTP headers, so maybe that filter should
      // be a prereq of this one.
      HtmlElement* added_viewport_element = driver()->NewElement(
          element, HtmlName::kMeta);
      added_viewport_element->set_style(HtmlElement::BRIEF_CLOSE);
      added_viewport_element->AddAttribute(
          driver()->MakeName(HtmlName::kName), "viewport",
          HtmlElement::SINGLE_QUOTE);
      added_viewport_element->AddAttribute(
          driver()->MakeName(HtmlName::kContent), kViewportContent,
          HtmlElement::SINGLE_QUOTE);
      driver()->InsertNodeAfterCurrent(added_viewport_element);

      /*
      HtmlElement* progress_script = driver()->NewElement(
          element->parent(),
          HtmlName::kScript);
      script->set_style(HtmlElement::EXPLICIT_CLOSE);
      driver()->InsertNodeAfterCurrent(script);
      driver()->AddAttribute(script, HtmlName::kSrc,
                             StrCat(static_file_prefix_, "mob_progress.js"));

      */
    }
  } else if (keyword == HtmlName::kBody) {
    ++body_element_depth_;
    if (use_js_layout_ && !added_progress_) {
      added_progress_ = true;
      HtmlElement* scrim = driver()->NewElement(element, HtmlName::kDiv);
      driver()->InsertNodeAfterCurrent(scrim);
      driver()->AddAttribute(scrim, HtmlName::kId, "ps-progress-scrim");
      driver()->AddAttribute(scrim, HtmlName::kClass, "psProgressScrim");

      HtmlElement* remove_bar = driver()->AppendAnchor(
          "javascript:psRemoveProgressBar();",
          "Remove Progress Bar (doesn't stop mobilization)",
          scrim);
      driver()->AddAttribute(remove_bar, HtmlName::kId,
                             "ps-progress-remove");
      if (!driver()->DebugMode()) {
        driver()->AppendChild(
            scrim, driver()->NewElement(scrim, HtmlName::kBr));
        driver()->AppendAnchor(
            "javascript:psSetDebugMode();",
            "Show Debug Log In Progress Bar",
          scrim);
        driver()->AddAttribute(remove_bar, HtmlName::kId,
                               "ps-progress-show-log");
      }

      const GoogleUrl& gurl = driver()->google_url();
      GoogleString origin_url, host;
      if (gurl.IsWebValid() &&
          driver()->options()->domain_lawyer()->StripProxySuffix(
              gurl, &origin_url, &host)) {
        driver()->AppendChild(
            scrim, driver()->NewElement(scrim, HtmlName::kBr));
        driver()->AppendAnchor(
            origin_url,
            "Abort mobilization and load page from origin",
            scrim);
      }
      HtmlElement* bar = driver()->NewElement(scrim, HtmlName::kDiv);
      driver()->AddAttribute(bar, HtmlName::kClass, "psProgressBar");
      driver()->AppendChild(scrim, bar);
      HtmlElement* span = driver()->NewElement(bar, HtmlName::kSpan);
      driver()->AddAttribute(span, HtmlName::kId, "ps-progress-span");
      driver()->AddAttribute(span, HtmlName::kClass, "psProgressSpan");
      driver()->AppendChild(bar, span);
      HtmlElement* log = driver()->NewElement(scrim, HtmlName::kPre);
      driver()->AddAttribute(log, HtmlName::kId, "ps-progress-log");
      driver()->AddAttribute(log, HtmlName::kClass, "psProgressLog");
      driver()->AppendChild(scrim, log);
    }
  } else if (body_element_depth_ > 0) {
    MobileRole::Level element_role = GetMobileRole(element);
    if (element_role != MobileRole::kInvalid) {
      if (keeper_element_depth_ == 0) {
        LogEncounteredBlock(element_role);
      }
      if (element_role == MobileRole::kKeeper) {
        ++keeper_element_depth_;
      }
    }
  }
}

void MobilizeRewriteFilter::AddStaticScript(StringPiece script) {
  // TODO(jmarantz): Consider using CommonFilter::InsertNodeAtBodyEnd.
  // TODO(jmarantz): Integrate with StaticAssetManager.
  GoogleString script_path = StrCat(static_file_prefix_, script);
  driver()->InsertScriptBeforeCurrent(script_path, true);
}

void MobilizeRewriteFilter::EndElementImpl(HtmlElement* element) {
  HtmlName::Keyword keyword = element->keyword();

  if (keyword == HtmlName::kScript) {
    in_script_ = false;
  }

  if (keyword == HtmlName::kBody) {
    --body_element_depth_;
    if (body_element_depth_ == 0) {
      if (use_js_layout_ || use_js_nav_ || use_js_logo_) {
        if (!added_mob_js_) {
          added_mob_js_ = true;

          if (use_js_layout_ && !rewrite_js_) {
            // Include the base closure file to allow goog.provide
            // etc to work.
            driver()->InsertScriptBeforeCurrent(
                "var CLOSURE_UNCOMPILED_DEFINES = "
                "{'goog.ENABLE_DEBUG_LOADER': false};",
                false);
            AddStaticScript("goog/base.js");
          }
          if (use_js_nav_) {
            HtmlElement* script =
                driver()->NewElement(element->parent(), HtmlName::kScript);
            script->set_style(HtmlElement::EXPLICIT_CLOSE);
            InsertNodeAtBodyEnd(script);
            StaticAssetManager* manager =
                driver()->server_context()->static_asset_manager();
            StringPiece js = manager->GetAsset(StaticAssetEnum::MOBILIZE_NAV_JS,
                                               driver()->options());
            manager->AddJsToElement(js, script, driver());
          }
          if (use_js_logo_) {
            AddStaticScript("mob_logo.js");
          }
          if (use_js_layout_) {
            if (rewrite_js_) {
              AddStaticScript("mob_jsc.js");
            } else {
              AddStaticScript("mob_util.js");
              AddStaticScript("mob_xhr.js");
              AddStaticScript("mob_layout.js");
              AddStaticScript("mob.js");
            }
          }
        }
      }
      reached_reorder_containers_ = false;
    }
  } else if (body_element_depth_ == 0 && keyword == HtmlName::kHead) {
    // TODO(jmarantz): this uses AppendChild, but probably should use
    // InsertBeforeCurrent to make it work with flush windows.
    AddStyle(element);

    // TODO(jmarantz): if we want to debug with Closure constructs, uncomment:
    // HtmlElement* script_element =
    //     driver()->NewElement(element, HtmlName::kScript);
    // driver()->AppendChild(element, script_element);
    // driver()->AddAttribute(script_element, HtmlName::kSrc,
    //                        StrCat(static_file_prefix_, "closure/base.js"));
  } else if (keeper_element_depth_ > 0) {
    MobileRole::Level element_role = GetMobileRole(element);
    if (element_role == MobileRole::kKeeper) {
      --keeper_element_depth_;
    }
  }
}

void MobilizeRewriteFilter::Characters(HtmlCharactersNode* characters) {
  if (in_script_) {
    // This is a temporary hack for removing a SPOF from
    // http://www.cardpersonalizzate.it/, whose reference
    // to a file in e.mouseflow.com hangs and stops the
    // browser from making progress.
    GoogleString* contents = characters->mutable_contents();
    if (contents->find("//e.mouseflow.com/projects") != GoogleString::npos) {
      *contents = StrCat("/*", *contents, "*/");
    }
  }
}

void MobilizeRewriteFilter::AppendStylesheet(const StringPiece& css_file_name,
                                             HtmlElement* element) {
  HtmlElement* link = driver()->NewElement(element, HtmlName::kLink);
  driver()->AppendChild(element, link);
  driver()->AddAttribute(link, HtmlName::kRel, "stylesheet");
  driver()->AddAttribute(link, HtmlName::kHref, StrCat(static_file_prefix_,
                                                       css_file_name));
}

void MobilizeRewriteFilter::AddStyle(HtmlElement* element) {
  if (!added_style_) {
    added_style_ = true;
    // <style>...</style>
    AppendStylesheet("lite.css", element);

    if (use_js_logo_) {
      AppendStylesheet("mob_logo.css", element);
    }

    // TODO(jud): Move mob_nav.css out of experimental.
    if (use_js_nav_) {
      AppendStylesheet("mob_nav.css", element);
    }
  }
}

const MobileRoleData*
MobileRoleData::FromString(const StringPiece& mobile_role) {
  for (int i = 0, n = arraysize(kMobileRoles); i < n; ++i) {
    if (mobile_role == kMobileRoles[i].value) {
      return &kMobileRoles[i];
    }
  }
  return NULL;
}

MobileRole::Level
MobileRoleData::LevelFromString(const StringPiece& mobile_role) {
  const MobileRoleData* role = FromString(mobile_role);
  if (role == NULL) {
    return MobileRole::kInvalid;
  } else {
    return role->level;
  }
}

MobileRole::Level MobilizeRewriteFilter::GetMobileRole(
    HtmlElement* element) {
  HtmlElement::Attribute* mobile_role_attribute =
      element->FindAttribute(HtmlName::kDataMobileRole);
  if (mobile_role_attribute) {
    return MobileRoleData::LevelFromString(
        mobile_role_attribute->escaped_value());
  } else {
    if (CheckForKeyword(kKeeperTags, kNumKeeperTags,
                        element->keyword())) {
      return MobileRole::kKeeper;
    }
    return MobileRole::kInvalid;
  }
}

bool MobilizeRewriteFilter::CheckForKeyword(
    const HtmlName::Keyword* sorted_list, int len, HtmlName::Keyword keyword) {
  return std::binary_search(sorted_list, sorted_list+len, keyword);
}

void MobilizeRewriteFilter::LogEncounteredBlock(MobileRole::Level level) {
  switch (level) {
    case MobileRole::kKeeper:
      num_keeper_blocks_->Add(1);
      break;
    case MobileRole::kHeader:
      num_header_blocks_->Add(1);
      break;
    case MobileRole::kNavigational:
      num_navigational_blocks_->Add(1);
      break;
    case MobileRole::kContent:
      num_content_blocks_->Add(1);
      break;
    case MobileRole::kMarginal:
      num_marginal_blocks_->Add(1);
      break;
    case MobileRole::kInvalid:
    case MobileRole::kUnassigned:
      // Should not happen.
      LOG(DFATAL) << "Attepted to move kInvalid or kUnassigned element";
      break;
  }
}

}  // namespace net_instaweb
