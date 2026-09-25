require 'xcodeproj'
project_path = 'Flow_1.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the target
target = project.targets.first

# Add the file to the Engines group
engines_group = project.main_group.find_subpath(File.join('Flow_1', 'Engines'), true)
file_ref = engines_group.new_reference('TextNormalizer.swift')

# Add to compile sources
target.source_build_phase.add_file_reference(file_ref)

project.save
