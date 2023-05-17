# frozen_string_literal: true

module CommandHelpers
  def command_output
    tmp_stderr = Tempfile.create

    allow_any_instance_of(Command::Base).to receive(:progress).and_return(tmp_stderr) # rubocop:disable RSpec/AnyInstance

    yield

    tmp_stderr.rewind
    output = tmp_stderr.read
    tmp_stderr.close

    output
  end
end
