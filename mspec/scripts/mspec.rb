#
# mspec - a spec runner for mini_rspec
#

require 'optparse'

module MSpec
  VERSION = '0.6.1'
end

# defaults
patterns = []
includes = []
requires = []
except = []
only = []
name = nil
output = nil
clean = false
target = 'shotgun/rubinius'
format = 'DottedFormatter'
verbose = false
flags = []
commas = false

opts = OptionParser.new("", 24, '   ') do |opts|
  opts.banner = "mspec [options] (FILE|DIRECTORY|GLOB)+"
  opts.separator ""

  opts.on("-f", "--format FORMAT", String, 
          "Formatter for reporting: s:specdox|d:dotted|c:ci|h:html|i:immediate") do |f|
    case f
    when 's', 'specdox', 'specdoc'
      format = 'SpecdocFormatter'
    when 'h', 'html'
      format = 'HtmlFormatter'
    when 'd', 'dot', 'dotted'
      format = 'DottedFormatter'
    when 'c', 'ci', 'integration'
      format = 'CIFormatter'
    when 'i', 'immediate'
      format = 'ImmediateFormatter'
    else
      puts "Unknown format: #{f}"
      puts opts
      exit
    end
  end
  opts.on("-t", "--target TARGET", String, 
          "Implementation that will run the specs: r:ruby|r19:ruby19|x:rbx|j:jruby") do |t|
    case t
    when 'r', 'ruby'
      target = 'ruby'
    when 'r19', 'ruby19'
      target = 'ruby19'
    when 'x', 'rbx', 'rubinius'
      target = 'shotgun/rubinius'
    when 'j', 'jruby'
      target = 'jruby'
    else
      target = t
    end
  end
  opts.on("-T", "--targetopt OPT", String,
          "Pass OPT as a flag to the target implementation") do |t|
    flags <<  t
  end
  opts.on("-I", "--include DIRECTORY", String,
          "Passes through as the -I option to the target") do |d|
    includes << "-I#{d}"
  end
  opts.on("-r", "--require LIBRARY", String,
          "Passes through as the -r option to the target") do |f|
    requires << "-r#{f}"
  end
  opts.on("-n", "--name RUBY_NAME", String,
          "Overrides the name used to determine the implementation") do |n|
    name = "RUBY_NAME = \"#{n}\";"
  end
  opts.on("-o", "--output FILE", String,
          "Reporter output will be sent to FILE") do |f|
    output = f
  end
  opts.on("-e", "--example STRING|FILE", String,
          "Execute example(s) with descriptions matching STRING or each line of FILE") do |r|
    only << r
  end
  opts.on("-x", "--exclude STRING|FILE", String,
          "Exclude example(s) with descriptions matching STRING or each line of FILE") do |r|
    except << r
  end
  opts.on("-C", "--clean", "Remove all compiled spec files first") do
    clean = true
  end
  opts.on("-g", "--gdb", "Run under gdb") do
    flags << '--gdb'
  end
  opts.on("-A", "--valgrind", "Run under valgrind") do
    flags << '--valgrind'
  end
  opts.on("-V", "--verbose", "Output each file processed when running") do
    verbose = true
  end
  opts.on("-,", "--comma", "Output a comma for each file processed") do
    commas = true
  end
  opts.on("-v", "--version", "Show version") do
    puts "Mini RSpec #{MSpec::VERSION}"
    exit
  end
  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
  
  patterns = opts.parse ARGV
end

if patterns.empty?
  puts "No files specified."
  puts opts
  exit
end

files = []
patterns.each do |item|
  stat = File.stat(File.expand_path(item))
  files << item if stat.file?
  files.concat(Dir[item+"/**/*_spec.rb"].sort) if stat.directory?
end

code = <<-EOC
ENV['MSPEC_RUNNER'] = '1'
require 'spec/spec_helper'

$VERBOSE=nil
#{name}
set_spec_runner(#{format}, #{output ? output.inspect : 'STDOUT'})
spec_runner.only(*#{only.inspect})
spec_runner.except(*#{except.inspect})
#{files.inspect}.each do |f|
  cname = "\#{f}c"
  File.delete(cname) if #{clean} and File.exist?(cname)
  STDERR.puts f if #{verbose}
  begin
    spec_runner.formatter.out << "," if #{commas}
    load f
  rescue Exception => e
    puts "\#{e} loading \#{f}"
  end
end
spec_runner.formatter.summary
EOC

Dir.mkdir "tmp" unless File.directory?("tmp")
File.open("tmp/last_mspec.rb", "w") do |f|
  f << code
end

cmd = "#{target} %s #{includes.join(" ")} #{requires.join(" ")} tmp/last_mspec.rb"
exec(cmd % flags.join(' '))