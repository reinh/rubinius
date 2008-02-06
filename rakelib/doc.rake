$redcloth_available = nil

begin
  require 'rubygems'
rescue LoadError
  # Don't show RedCloth warning if gems aren't available
  $redcloth_available = false
end

## Include tasks to build documentation
def redcloth_present?
  if $redcloth_available.nil?
    begin
      require 'redcloth'
      $redcloth_available = true
    rescue Exception
      puts
      puts "WARNING: RedCloth 3.x is required to build the VM html docs"
      puts "Run 'gem install redcloth' to install the latest RedCloth gem"
      puts
      $redcloth_available = false
    end
  end
  $redcloth_available
end

namespace "doc" do
  namespace "vm" do

    desc "Remove all generated HTML files under doc/vm"
    task "clean" do
      Dir.glob('doc/vm/**/*.html').each do |html|
        rm_f html unless html =~ /\/?index.html$/
      end
    end

    desc "Generate HTML in doc/vm from YAML and Textile sources"
    task "html"
    
    begin
      # Define tasks for each opcode html file on the corresponding YAML file
      require 'doc/vm/op_code_info'
      OpCode::Info.op_codes.each do |op|
        html = "doc/vm/op_codes/#{op}.html"
        yaml = "doc/vm/op_codes/#{op}.yaml"
        file html do
          cd 'doc/vm' do
            ruby "gen_op_code_html.rb #{op}"
          end
        end
        file html => yaml if File.exists?("doc/vm/op_codes/#{op}.yaml")

        task "html" => html
      end

    rescue LoadError

    end

    # Define tasks for each section html file on the corresponding textile file
    # Note: requires redcloth gem to convert textile markup to html
    Dir.glob('doc/vm/*.textile').each do |f|
      html = f.chomp('.textile') + '.html'
      file html => f do
        if redcloth_present?
          section = File.basename(f)
          cd 'doc/vm' do
            ruby "gen_section_html.rb #{section}"
          end
        end
      end

      task "html" => html
    end
  end
end
