#!/usr/bin/env python3
"""Generate a minimal but valid Xcode project for Project Link iOS."""
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1] / "ios" / "ProjectLink"
SRC = ROOT / "ProjectLink"

def uid():
    return uuid.uuid4().hex[:24].upper()

files = [
    "ProjectLinkApp.swift",
    "ContentView.swift",
    "Net/Protocol.swift",
    "Net/LinkClient.swift",
    "Net/ScreenStreams.swift",
    "Theme/RainbowTheme.swift",
    "Views/PairingView.swift",
    "Views/TouchpadView.swift",
    "Views/KeyboardView.swift",
    "Views/LiveScreenView.swift",
    "Views/ClipboardFilesView.swift",
]

ids = {f: uid() for f in files}
ids["assets"] = uid()
ids["info"] = uid()
ids["src_group"] = uid()
ids["net_group"] = uid()
ids["views_group"] = uid()
ids["theme_group"] = uid()
ids["product"] = uid()
ids["target"] = uid()
ids["project"] = uid()
ids["sources_phase"] = uid()
ids["resources_phase"] = uid()
ids["frameworks_phase"] = uid()
ids["main_group"] = uid()
ids["products_group"] = uid()
ids["config_list_proj"] = uid()
ids["config_list_tgt"] = uid()
ids["debug_proj"] = uid()
ids["release_proj"] = uid()
ids["debug_tgt"] = uid()
ids["release_tgt"] = uid()

def fileref(path, fid):
    name = Path(path).name
    return f'''\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'''

file_refs = "\n".join(fileref(f, ids[f]) for f in files)
file_refs += f'''
\t\t{ids["assets"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
\t\t{ids["info"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{ids["product"]} /* ProjectLink.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ProjectLink.app; sourceTree = BUILT_PRODUCTS_DIR; }};'''

build_files = "\n".join(
    f'\t\t{uid()} /* {Path(f).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ids[f]} /* {Path(f).name} */; }};'
    for f in files
)
assets_build = uid()
build_files += f'\n\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ids["assets"]} /* Assets.xcassets */; }};'

# Keep stable build file ids for sources phase listing — regenerate map
source_build_ids = {f: uid() for f in files}
build_files = "\n".join(
    f'\t\t{source_build_ids[f]} /* {Path(f).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ids[f]} /* {Path(f).name} */; }};'
    for f in files
)
build_files += f'\n\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ids["assets"]} /* Assets.xcassets */; }};'

sources_list = "\n".join(f'\t\t\t\t{source_build_ids[f]} /* {Path(f).name} in Sources */,' for f in files)

pbx = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{build_files}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_refs}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{ids["frameworks_phase"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids["main_group"]} = {{
			isa = PBXGroup;
			children = (
				{ids["src_group"]} /* ProjectLink */,
				{ids["products_group"]} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{ids["products_group"]} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids["product"]} /* ProjectLink.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{ids["src_group"]} /* ProjectLink */ = {{
			isa = PBXGroup;
			children = (
				{ids["ProjectLinkApp.swift"]} /* ProjectLinkApp.swift */,
				{ids["ContentView.swift"]} /* ContentView.swift */,
				{ids["net_group"]} /* Net */,
				{ids["theme_group"]} /* Theme */,
				{ids["views_group"]} /* Views */,
				{ids["assets"]} /* Assets.xcassets */,
				{ids["info"]} /* Info.plist */,
			);
			path = ProjectLink;
			sourceTree = "<group>";
		}};
		{ids["net_group"]} /* Net */ = {{
			isa = PBXGroup;
			children = (
				{ids["Net/Protocol.swift"]} /* Protocol.swift */,
				{ids["Net/LinkClient.swift"]} /* LinkClient.swift */,
				{ids["Net/ScreenStreams.swift"]} /* ScreenStreams.swift */,
			);
			path = Net;
			sourceTree = "<group>";
		}};
		{ids["theme_group"]} /* Theme */ = {{
			isa = PBXGroup;
			children = (
				{ids["Theme/RainbowTheme.swift"]} /* RainbowTheme.swift */,
			);
			path = Theme;
			sourceTree = "<group>";
		}};
		{ids["views_group"]} /* Views */ = {{
			isa = PBXGroup;
			children = (
				{ids["Views/PairingView.swift"]} /* PairingView.swift */,
				{ids["Views/TouchpadView.swift"]} /* TouchpadView.swift */,
				{ids["Views/KeyboardView.swift"]} /* KeyboardView.swift */,
				{ids["Views/LiveScreenView.swift"]} /* LiveScreenView.swift */,
				{ids["Views/ClipboardFilesView.swift"]} /* ClipboardFilesView.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids["target"]} /* ProjectLink */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids["config_list_tgt"]} /* Build configuration list for PBXNativeTarget "ProjectLink" */;
			buildPhases = (
				{ids["sources_phase"]} /* Sources */,
				{ids["frameworks_phase"]} /* Frameworks */,
				{ids["resources_phase"]} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ProjectLink;
			productName = ProjectLink;
			productReference = {ids["product"]} /* ProjectLink.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids["project"]} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
			}};
			buildConfigurationList = {ids["config_list_proj"]} /* Build configuration list for PBXProject "ProjectLink" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ids["main_group"]};
			productRefGroup = {ids["products_group"]} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids["target"]} /* ProjectLink */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids["resources_phase"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{assets_build} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids["sources_phase"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{sources_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{ids["debug_proj"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				GCC_DYNAMIC_NO_PIC = NO;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{ids["release_proj"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{ids["debug_tgt"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ProjectLink/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.noco.projectlink;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{ids["release_tgt"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ProjectLink/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.noco.projectlink;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids["config_list_proj"]} /* Build configuration list for PBXProject "ProjectLink" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids["debug_proj"]} /* Debug */,
				{ids["release_proj"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids["config_list_tgt"]} /* Build configuration list for PBXNativeTarget "ProjectLink" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids["debug_tgt"]} /* Debug */,
				{ids["release_tgt"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {ids["project"]} /* Project object */;
}}
'''

out = ROOT / "ProjectLink.xcodeproj" / "project.pbxproj"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(pbx, encoding="utf-8")

# Update AppIcon contents to reference PNG
icon_json = ROOT / "ProjectLink" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
icon_json.write_text('''{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
''', encoding="utf-8")
print("Wrote", out)
