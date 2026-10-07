require 'xcodeproj'

project_path = 'ePdfUB.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'ePdfUB' }

phase = target.shell_script_build_phases.find { |p| p.name == 'Remove Non-Nano Models for Release' }
if phase
  phase.remove_from_project
  project.save
  puts "Build phase removed."
end
