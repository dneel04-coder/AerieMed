#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds the ResqruckWidgetExtension WidgetKit target to Runner.xcodeproj.
#
# Run on Codemagic's Mac runner (before `pod install`), not by hand-editing
# project.pbxproj: the pbxproj format is fragile to hand-edit blind, and this
# is developed on Windows with no Xcode available to validate a manual edit
# before it reaches CI. Uses the `xcodeproj` gem (install via
# `gem install xcodeproj`) -- the same tool fastlane/CI pipelines use for
# this exact kind of programmatic Xcode project surgery.
#
# Idempotent: running this again on a project that already has the target
# is a no-op, so it's safe to run on every CI build.

require 'xcodeproj'

PROJECT_PATH = File.join(__dir__, 'Runner.xcodeproj')
TARGET_NAME = 'ResqruckWidgetExtension'
BUNDLE_ID = 'com.peninsulathreat.resqruck.widget'
APP_GROUP = 'group.com.peninsulathreat.resqruck'
DEPLOYMENT_TARGET = '15.0'
EXTENSION_DIR = File.join(__dir__, TARGET_NAME)

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "#{TARGET_NAME} already present in project.pbxproj -- nothing to do."
  exit 0
end

runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Could not find the Runner target in #{PROJECT_PATH}" if runner_target.nil?

# ── New target ────────────────────────────────────────────────────────────
widget_target = project.new_target(:app_extension, TARGET_NAME, :ios, DEPLOYMENT_TARGET)

# ── Source group + file references ───────────────────────────────────────
group = project.main_group.new_group(TARGET_NAME, EXTENSION_DIR)
swift_files = %w[ResqruckWidgetBundle.swift ResqruckWidget.swift].map do |name|
  group.new_file(File.join(EXTENSION_DIR, name))
end
info_plist_ref = group.new_file(File.join(EXTENSION_DIR, 'Info.plist'))
entitlements_ref = group.new_file(File.join(EXTENSION_DIR, "#{TARGET_NAME}.entitlements"))

swift_files.each { |ref| widget_target.source_build_phase.add_file_reference(ref) }

# ── Frameworks ────────────────────────────────────────────────────────────
widget_target.frameworks_build_phase.add_file_reference(
  project.frameworks_group.new_file('System/Library/Frameworks/WidgetKit.framework')
)
widget_target.frameworks_build_phase.add_file_reference(
  project.frameworks_group.new_file('System/Library/Frameworks/SwiftUI.framework')
)

# ── Build settings ────────────────────────────────────────────────────────
widget_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => "#{TARGET_NAME}/Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'CODE_SIGN_ENTITLEMENTS' => "#{TARGET_NAME}/#{TARGET_NAME}.entitlements",
    'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'SKIP_INSTALL' => 'YES',
    'MARKETING_VERSION' => '1.0',
    'CURRENT_PROJECT_VERSION' => '1',
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks',
    ],
  )
end

# ── Wire the extension into Runner: dependency + embed ───────────────────
runner_target.add_dependency(widget_target)

embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed App Extensions'
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.add_file_reference(widget_target.product_reference, true)

# Must run before Flutter's own "Run Script" build phase, or the extension
# isn't embedded by the time flutter build ipa packages the app -- see
# https://docs.flutter.dev/platform-integration/ios/app-extensions.
runner_target.build_phases.unshift(embed_phase)

# ── App Group on the main app too (Runner.entitlements already has it
# committed in the repo; this only needs pointing CODE_SIGN_ENTITLEMENTS at
# it if a fresh/differently-generated project ever lacked that setting) ───
runner_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] ||= 'Runner/Runner.entitlements'
end

project.save
puts "Added #{TARGET_NAME} (#{BUNDLE_ID}) to #{PROJECT_PATH}."
