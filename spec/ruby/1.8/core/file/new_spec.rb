require File.dirname(__FILE__) + '/../../spec_helper'

describe "File.new" do
  before :each do 
    @file = 'test.txt'
    @fh = nil 
    @flags = File::CREAT | File::TRUNC | File::WRONLY
    File.open(@file, "w") {} # touch
  end

  after :each do   
    File.delete(@file) if File.exists?(@file)
    @fh    = nil
    @file  = nil
    @flags = nil
  end

  it "return a new File with mode string" do
    @fh = File.new(@file, 'w')
    @fh.class.should == File
    File.exists?(@file).should == true
  end

  it "return a new File with mode num" do   
    @fh = File.new(@file, @flags) 
    @fh.class.should == File
    File.exists?(@file).should == true
  end

  it "return a new File with modus num and premissions " do 
    File.delete(@file) 
    @fh = File.new(@file, @flags, 0755)
    @fh.class.should == File
    File.stat(@file).mode.to_s(8).should == "100755"
    File.exists?(@file).should == true
  end

  it "return a new File with modus fd " do 
    @fh = File.new(@file) 
    @fh = File.new(@fh.fileno) 
    @fh.class.should == File
    File.exists?(@file).should == true
  end
  
  it "create a new file when use File::EXCL mode " do 
    @fh = File.new(@file, File::EXCL) 
    @fh.class.should == File
    File.exists?(@file).should == true
  end

  it "raise an Errorno::EEXIST if the file exists when create a new file with File::CREAT|File::EXCL" do 
    lambda { @fh = File.new(@file, File::CREAT|File::EXCL) }.should raise_error(Errno::EEXIST)
  end
  
  it "create a new file when use File::WRONLY|File::APPEND mode" do 
    @fh = File.new(@file, File::WRONLY|File::APPEND) 
    @fh.class.should == File
    File.exists?(@file).should == true
  end

  it "raise an Errno::EINVAL error with File::APPEND" do 
    lambda { @fh = File.new(@file, File::APPEND) }.should raise_error(Errno::EINVAL)
  end
  
  
  it "raise an Errno::EINVAL error with File::RDONLY|File::APPEND" do 
    lambda { @fh = File.new(@file, File::RDONLY|File::APPEND) }.should raise_error(Errno::EINVAL)
  end
  
  it "raise an Errno::EINVAL error with File::RDONLY|File::WRONLY" do 
    @fh = File.new(@file, File::RDONLY|File::WRONLY)
    @fh.class.should == File
    File.exists?(@file).should == true
  end
  
  
  it "create a new file when use File::WRONLY|File::TRUNC mode" do 
    @fh = File.new(@file, File::WRONLY|File::TRUNC) 
    @fh.class.should == File
    File.exists?(@file).should == true
  end
  
  specify  "expected errors " do
    lambda { File.new(true)  }.should raise_error(TypeError)
    lambda { File.new(false) }.should raise_error(TypeError)
    lambda { File.new(nil)   }.should raise_error(TypeError)
    lambda { File.new(-1) }.should raise_error(Errno::EBADF)
    lambda { File.new(@file, File::CREAT, 0755, 'test') }.should raise_error(ArgumentError)
  end

  # You can't alter mode or permissions when opening a file descriptor
  #
  it "can't alter mode or permissions when opening a file" do 
    @fh = File.new(@file)
    lambda { File.new(@fh.fileno, @flags) }.should raise_error(Errno::EINVAL)
  end
end 