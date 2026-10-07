require 'xcodeproj'

project_path = 'ePdfUB.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'ePdfUB' }

# Check if script already exists
existing_phase = target.shell_script_build_phases.find { |p| p.name == 'Remove Non-Nano Models for Release' }
if existing_phase.nil?
  phase = target.new_shell_script_build_phase('Remove Non-Nano Models for Release')
  phase.shell_script = <<~SCRIPT
if [ "${CONFIGURATION}" = "Release" ]; then
    echo "Removing Small and Medium models from Release build..."
    rm -rf "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/yolo26s-doclaynet.mlmodelc"
    rm -rf "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/yolo26m-doclaynet.mlmodelc"
fi
SCRIPT
  project.save
  puts "Build phase added."
else
  puts "Build phase already exists."
end
