class MonotonicityError < StandardError
end

class ArgumentError < StandardError
end

class Spy

  EXIT_BAD_ARGUMENTS = 2
  EXIT_MONOTONICITY = 3

  SPY_PATH = File.join( File.dirname( __FILE__ ), "spy" )

  attr_accessor :elf_path, :threshold, :slot

  def initialize(elf_path = nil)
    @elf_path = elf_path
    @threshold = 120
    @slot = 2048
    @probes = []
    @spy_io = nil
    @whole_output = nil
  end

  def addProbe(name, address)
    if name =~ /\A[A-Za-z]\Z/
      @probes << name + ':0x' + address.to_s(16)
    else
      raise ArgumentError.new("Name must be exactly one alphabet character.")
    end
  end

  def start
    if @elf_path.nil?
      raise ArgumentError.new("The elf_path is not set.")
    end

    unless @spy_io.nil?
      raise ArgumentError.new("Already started.")
    end

    if @probes.empty?
      raise ArgumentError.new("There are no probes.")
    end

    command = [
        SPY_PATH,
        "-e", @elf_path,
        "-s", @slot.to_s,
        "-t", @threshold.to_s
      ]
    @probes.each do |probe|
      command << "-p"
      command << probe
    end

    @spy_io = IO.popen(command, "r")
    @whole_output = ""
    # TODO: check error exits
  end

  def stop
    Process.kill("KILL", @spy_io.pid)
    # Read any remaining output.
    # FIXME: this might block if there was no output
    @whole_output += parse_output(@spy_io.read)
    @spy_io.close
    @spy_io = nil
    return @whole_output
  end

  def each_burst
    loop do
      begin
        output = ""
        @spy_io.read_nonblock(10_000, output)
        output = parse_output(output)
        @whole_output += output
        yield output
      rescue IO::WaitReadable
        # Wait and try again later.
      rescue EOFError
        @spy_io.close
        if $?.exitstatus == EXIT_BAD_ARGUMENTS
          raise ArgumentError.new("Spy program says bad arguments.")
        elsif $?.exitstatus == EXIT_MONOTONICITY
          raise MonotonicityError.new("RDTSC behaved non-monotonically.")
        else
          raise ArgumentError.new("Unknown error.")
        end
      end
      sleep 1
    end
  end

  def parse_output(raw_output)

    if raw_output.include? "Monotonicity failure"
      raise MonotonicityError.new("RDTSC behaved non-monotonically.")
    end

    lines = raw_output.split("\n")
    lines.reject! { |l| l.include? "WARNING" }

    return lines.join
  end

end
