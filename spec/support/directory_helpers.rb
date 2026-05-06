# frozen_string_literal: true

module DirectoryHelpers
  def inside_dir(path)
    original_working_dir = Dir.pwd
    Dir.chdir(path)
    yield if block_given?
  ensure
    Dir.chdir(original_working_dir)
  end
end
