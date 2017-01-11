#!/usr/bin/ruby

# Tweak the .xcodeproj after creating with with swift package manager.

# Resources: 
# http://stackoverflow.com/questions/20072937/add-run-script-build-phase-to-xcode-project-from-podspec
# https://github.com/IBM-Swift/Kitura-Build/blob/master/build/fix_xcode_project.rb
# http://www.rubydoc.info/github/CocoaPods/Xcodeproj/Xcodeproj%2FProject%2FObject%2FAbstractTarget%3Anew_shell_script_build_phase
# http://www.rubydoc.info/github/CocoaPods/Xcodeproj/Xcodeproj/Project/Object/AbstractTarget
# https://gist.github.com/niklasberglund/129065e2612d00c811d0
# https://github.com/CocoaPods/Xcodeproj
# http://stackoverflow.com/questions/34367048/how-do-you-automate-do-copy-files-in-build-phases-using-a-cocoapods-post-insta?rq=1

require 'xcodeproj'

path_to_project = "Server.xcodeproj"
project = Xcodeproj::Project.open(path_to_project)

# 1) Add Copy Files Phase for Server.plist to the Products directory for Server target
target = project.targets.select { |target| target.name == 'Server' }.first
puts "Updating #{target}"
phase = target.new_copy_files_build_phase()
	
# Contrary to the docs (see http://www.rubydoc.info/github/CocoaPods/Xcodeproj/Xcodeproj/Project/Object/PBXCopyFilesBuildPhase) I believe this is not a path, but rather a code, e.g., 16 indicates to copy the file to the Products Directory.
phase.dst_subfolder_spec = "16"

fileRef = project.new(Xcodeproj::Project::Object::PBXFileReference)
fileRef.path = 'Server.plist'

phase.add_file_reference(fileRef)	

# 2) Add in script phase for testing target-- because I haven't figured out to get access to the Products directory at test-run time.
target = project.targets.select { |target| target.name == 'ServerTests' }.first
puts "Updating #{target}"
phase = target.new_shell_script_build_phase()
phase.shell_script = "cp Server.plist /tmp"

project.save()