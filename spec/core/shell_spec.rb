# frozen_string_literal: true

require "spec_helper"

describe Shell do
  describe ".use_tmp_stderr" do
    it "provides a tempfile for the duration of the block and clears it afterwards" do
      captured_tmp_stderr = nil
      captured_message = nil

      described_class.use_tmp_stderr do
        captured_tmp_stderr = described_class.tmp_stderr
        described_class.write_to_tmp_stderr("some error\n")
        captured_message = described_class.read_from_tmp_stderr
      end

      expect(captured_tmp_stderr).not_to be_nil
      expect(captured_message).to eq("some error")
      expect(described_class.tmp_stderr).to be_nil
    end
  end

  describe ".read_from_tmp_stderr" do
    it "strips surrounding whitespace from the captured message" do
      message = nil

      described_class.use_tmp_stderr do
        described_class.write_to_tmp_stderr("  padded error  \n\n")
        message = described_class.read_from_tmp_stderr
      end

      expect(message).to eq("padded error")
    end
  end

  describe ".color" do
    it "delegates to the Thor shell" do
      thor_shell = described_class.send(:shell)
      allow(thor_shell).to receive(:set_color).with("hello", :red).and_return("\e[31mhello\e[0m")

      expect(described_class.color("hello", :red)).to eq("\e[31mhello\e[0m")
    end
  end

  describe ".confirm" do
    it "returns true when the user confirms" do
      thor_shell = described_class.send(:shell)
      allow(thor_shell).to receive(:yes?).with("Delete app? (y/N)").and_return(true)

      expect(described_class.confirm("Delete app?")).to be(true)
    end

    it "returns false when the user declines" do
      thor_shell = described_class.send(:shell)
      allow(thor_shell).to receive(:yes?).with("Delete app? (y/N)").and_return(false)

      expect(described_class.confirm("Delete app?")).to be(false)
    end
  end

  describe ".info" do
    it "says the message through the Thor shell" do
      thor_shell = described_class.send(:shell)
      allow(thor_shell).to receive(:say)

      described_class.info("deploying")

      expect(thor_shell).to have_received(:say).with("deploying")
    end
  end

  describe ".warn" do
    it "warns with a yellow WARNING prefix" do
      allow(Kernel).to receive(:warn)
      allow(described_class).to receive(:color)
        .with("WARNING: something is off", :yellow)
        .and_return("[yellow]WARNING: something is off")

      described_class.warn("something is off")

      expect(Kernel).to have_received(:warn).with("[yellow]WARNING: something is off")
    end
  end

  describe ".warn_deprecated" do
    it "warns with a yellow DEPRECATED prefix" do
      allow(Kernel).to receive(:warn)
      allow(described_class).to receive(:color)
        .with("DEPRECATED: old flag", :yellow)
        .and_return("[yellow]DEPRECATED: old flag")

      described_class.warn_deprecated("old flag")

      expect(Kernel).to have_received(:warn).with("[yellow]DEPRECATED: old flag")
    end
  end

  describe ".abort" do
    before do
      allow(Kernel).to receive(:warn)
    end

    it "warns with a red ERROR prefix and exits with the default error status" do
      allow(described_class).to receive(:color)
        .with("ERROR: it broke", :red)
        .and_return("[red]ERROR: it broke")

      expect { described_class.abort("it broke") }.to raise_error(
        an_instance_of(SystemExit).and(having_attributes(status: ExitCode::ERROR_DEFAULT))
      )
      expect(Kernel).to have_received(:warn).with("[red]ERROR: it broke")
    end

    it "exits with a custom exit status when given" do
      expect { described_class.abort("not found", ExitCode::NOT_FOUND) }.to raise_error(
        an_instance_of(SystemExit).and(having_attributes(status: ExitCode::NOT_FOUND))
      )
    end
  end

  describe ".verbose_mode" do
    after do
      described_class.verbose_mode(false)
    end

    it "updates the verbose flag" do
      expect { described_class.verbose_mode(true) }
        .to change(described_class, :verbose).to(true)
    end
  end

  describe ".debug" do
    after do
      described_class.verbose_mode(false)
    end

    context "when verbose mode is off" do
      it "does not warn" do
        allow(Kernel).to receive(:warn)

        described_class.debug("CMD", "cpln get gvc")

        expect(Kernel).not_to have_received(:warn)
      end
    end

    context "when verbose mode is on" do
      before do
        described_class.verbose_mode(true)
        allow(Kernel).to receive(:warn)
        allow(described_class).to receive(:color).with("CMD", :red).and_return("CMD")
      end

      it "warns with the prefix and message" do
        described_class.debug("CMD", "cpln get gvc")

        expect(Kernel).to have_received(:warn).with("\n[CMD] cpln get gvc")
      end

      it "hides sensitive data matching the pattern" do
        described_class.debug("CMD", "cpln login --token abcd1234", sensitive_data_pattern: /(?<=--token )(\S+)/)

        expect(Kernel).to have_received(:warn).with("\n[CMD] cpln login --token XXXXXXX")
      end
    end
  end

  describe ".should_hide_output?" do
    after do
      described_class.verbose_mode(false)
    end

    it "is truthy when capturing stderr and not verbose" do
      result = nil

      described_class.use_tmp_stderr do
        result = described_class.should_hide_output?
      end

      expect(result).to be_truthy
    end

    it "is falsey when not capturing stderr" do
      result = described_class.should_hide_output?

      expect(result).to be_falsey
    end

    it "is falsey when verbose mode is on" do
      described_class.verbose_mode(true)
      result = nil

      described_class.use_tmp_stderr do
        result = described_class.should_hide_output?
      end

      expect(result).to be_falsey
    end
  end

  describe ".cmd" do
    it "returns the output and success for a successful command" do
      result = described_class.cmd("echo", "hello")

      expect(result).to eq(output: "hello\n", success: true)
    end

    it "returns success false for a failing command" do
      result = described_class.cmd("sh", "-c", "exit 3")

      expect(result[:success]).to be(false)
    end

    it "merges stderr into the output when capture_stderr is true" do
      result = described_class.cmd("sh", "-c", "echo captured-err >&2; echo captured-out", capture_stderr: true)

      expect(result[:output]).to include("captured-err")
      expect(result[:output]).to include("captured-out")
      expect(result[:success]).to be(true)
    end

    it "does not capture stderr by default" do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture2).with("some", "command").and_return(["stdout only\n", status])

      result = described_class.cmd("some", "command")

      expect(result).to eq(output: "stdout only\n", success: true)
    end
  end

  describe ".hide_sensitive_data" do
    it "replaces matches of the pattern" do
      filtered = described_class.hide_sensitive_data("cpln login --token abcd1234", /(?<=--token )(\S+)/)

      expect(filtered).to eq("cpln login --token XXXXXXX")
    end

    it "returns the message untouched without a pattern" do
      expect(described_class.hide_sensitive_data("cpln login --token abcd1234")).to eq("cpln login --token abcd1234")
    end

    it "returns the message untouched when the pattern is not a Regexp" do
      filtered = described_class.hide_sensitive_data("cpln login --token abcd1234", "--token")

      expect(filtered).to eq("cpln login --token abcd1234")
    end
  end

  describe ".trap_interrupt" do
    it "registers a SIGINT handler that exits with the interrupt exit code" do
      handler = nil
      allow(described_class).to receive(:trap) { |_signal, &block| handler = block }
      allow(described_class).to receive(:puts)

      described_class.trap_interrupt

      expect(described_class).to have_received(:trap).with("SIGINT")
      expect { handler.call }.to raise_error(
        an_instance_of(SystemExit).and(having_attributes(status: ExitCode::INTERRUPT))
      )
    end
  end
end
