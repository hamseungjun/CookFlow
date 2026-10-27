"""Regenerate the dependency-free iOS Xcode project from checked-in sources."""
from pathlib import Path
import hashlib
import json
root = Path(__file__).resolve().parents[1]
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quoted(value): return json.dumps(str(value))
files = sorted((root / 'CookFlow').rglob('*.swift'))
resources = ['CookFlow/Assets.xcassets', 'CookFlow/PrivacyInfo.xcprivacy']
objects = []
def obj(key, text): objects.append(f'{uid(key)} = {{ {text} }};'); return uid(key)
source_ids = []
children = []
for path in files:
    relative = str(path.relative_to(root))
    file_id = obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;')
    children.append(file_id)
    source_ids.append(obj('build:'+relative, f'isa = PBXBuildFile; fileRef = {file_id};'))
resource_ids = []
for relative in resources:
    filetype = 'folder.assetcatalog' if relative.endswith('xcassets') else 'text.xml'
    file_id = obj(relative, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;')
    children.append(file_id)
    resource_ids.append(obj('build:'+relative, f'isa = PBXBuildFile; fileRef = {file_id};'))
product_id = obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CookFlow.app; sourceTree = BUILT_PRODUCTS_DIR;')
product_group = obj('products', f'isa = PBXGroup; children = ({product_id}); name = Products; sourceTree = "<group>";')
main_group = obj('mainGroup', f'isa = PBXGroup; children = ({", ".join(children + [product_group])}); sourceTree = "<group>";')
sources = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_ids)}); runOnlyForDeploymentPostprocessing = 0;')
resources_phase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(resource_ids)}); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for name in ['Debug', 'Release']:
    project_settings = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '5.0', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'}
    if name == 'Debug': project_settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'})
    else: project_settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-O','SWIFT_COMPILATION_MODE':'wholemodule'})
    target_settings = {'PRODUCT_BUNDLE_IDENTIFIER':'com.cookflow.ios', 'PRODUCT_NAME':'$(TARGET_NAME)', 'INFOPLIST_FILE':'CookFlow/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO', 'TARGETED_DEVICE_FAMILY':'1,2', 'CODE_SIGN_STYLE':'Automatic', 'MARKETING_VERSION':'1.0', 'CURRENT_PROJECT_VERSION':'1', 'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor', 'SWIFT_EMIT_LOC_STRINGS':'YES', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST':'NO', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks', 'ENABLE_PREVIEWS':'YES'}
    def settings(values): return ' '.join(f'{k} = {quoted(v)};' for k,v in values.items())
    project_configs.append(obj('project:'+name, f'isa = XCBuildConfiguration; buildSettings = {{ {settings(project_settings)} }}; name = {name};'))
    target_configs.append(obj('target:'+name, f'isa = XCBuildConfiguration; buildSettings = {{ {settings(target_settings)} }}; name = {name};'))
project_config_list = obj('projectConfigs', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_config_list = obj('targetConfigs', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(target_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {target_config_list}; buildPhases = ({sources}, {frameworks}, {resources_phase}); buildRules = (); dependencies = (); name = CookFlow; productName = CookFlow; productReference = {product_id}; productType = "com.apple.product-type.application";')
project = obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko, en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
(root/'CookFlow.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(objects) + '\n}; rootObject = '+project+'; }\n')
(root/'CookFlow.xcodeproj/xcshareddata/xcschemes/CookFlow.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CookFlow.app" BlueprintName="CookFlow" ReferencedContainer="container:CookFlow.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CookFlow.app" BlueprintName="CookFlow" ReferencedContainer="container:CookFlow.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CookFlow.app" BlueprintName="CookFlow" ReferencedContainer="container:CookFlow.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated iPhone + iPad project with {len(files)} Swift files')
