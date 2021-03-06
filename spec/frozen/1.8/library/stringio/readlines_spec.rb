require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/fixtures/classes'

describe "StringIO#readlines when passed [seperator]" do
  before(:each) do
    @io = StringIO.new("this>is>an>example")
  end

  it "returns an Array containing lines based on the passed seperator" do
    @io.readlines(">").should == ["this>", "is>", "an>", "example"]
  end

  it "updates self's position based on the number of read bytes" do
    @io.readlines(">")
    @io.pos.should eql(18)
  end

  it "updates self's lineno based on the number of read lines" do
    @io.readlines(">")
    @io.lineno.should eql(4)
  end

  it "does not change $_" do
    $_ = "test"
    @io.readlines(">")
    $_.should == "test"
  end

  it "returns an Array containing all paragraphs when the passed seperator is an empty String" do
    io = StringIO.new("this is\n\nan example")
    io.readlines("").should == ["this is\n", "an example"]
  end
  
  it "returns the remaining content as one line starting at the current position when passed nil" do
    io = StringIO.new("this is\n\nan example")
    io.pos = 5
    io.readlines(nil).should == ["is\n\nan example"]
  end

  it "tries to convert the passed seperator to a String using #to_str" do
    obj = mock('to_str')
    obj.stub!(:to_str).and_return(">")
    @io.readlines(obj).should == ["this>", "is>", "an>", "example"]
  end

  ruby_version_is "" ... "1.8.7" do
    it "checks whether the passed seperator responds to #to_str" do
      obj = mock('method_missing to_str')
      obj.should_receive(:respond_to?).any_number_of_times.with(:to_str).and_return(true)
      obj.should_receive(:method_missing).any_number_of_times.with(:to_str).and_return(">")
      @io.readlines(obj).should == ["this>", "is>", "an>", "example"]
    end
  end

  ruby_version_is "1.8.7" do
    it "checks whether the passed seperator responds to #to_str (including private methods)" do
      obj = mock('method_missing to_str')
      obj.should_receive(:respond_to?).any_number_of_times.with(:to_str, true).and_return(true)
      obj.should_receive(:method_missing).any_number_of_times.with(:to_str).and_return(">")
      @io.readlines(obj).should == ["this>", "is>", "an>", "example"]
    end
  end
end

describe "StringIO#readlines when passed no argument" do
  before(:each) do
    @io = StringIO.new("this is\nan example\nfor StringIO#readlines")
  end
  
  it "returns an Array containing lines based on $/" do
    begin
      old_sep, $/ = $/, " "
      @io.readlines.should == ["this ", "is\nan ", "example\nfor ", "StringIO#readlines"]
    ensure
      $/ = old_sep
    end
  end
  
  it "updates self's position based on the number of read bytes" do
    @io.readlines
    @io.pos.should eql(41)
  end
  
  it "updates self's lineno based on the number of read lines" do
    @io.readlines
    @io.lineno.should eql(3)
  end

  it "does not change $_" do
    $_ = "test"
    @io.readlines(">")
    $_.should == "test"
  end
  
  it "returns an empty Array when self is at the end" do
    @io.pos = 41
    @io.readlines.should == []
  end
end

describe "StringIO#readlines when in write-only mode" do
  it "raises an IOError" do
    io = StringIO.new("xyz", "w")
    lambda { io.readlines }.should raise_error(IOError)

    io = StringIO.new("xyz")
    io.close_read
    lambda { io.readlines }.should raise_error(IOError)
  end
end