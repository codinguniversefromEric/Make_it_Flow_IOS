require 'xcodeproj'

project_path = 'ePdfUB.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  next unless target.name == 'ePdfUB'
  target.build_configurations.each do |config|
    if config.name == 'Release'
      config.build_settings['EXCLUDED_SOURCE_FILE_NAMES'] = 'yolo26m-doclaynet.mlpackage yolo26s-doclaynet.mlpackage'
      puts "Added EXCLUDED_SOURCE_FILE_NAMES to #{target.name} for #{config.name}"
    end
  end
end

project.save
puts "Saved."
