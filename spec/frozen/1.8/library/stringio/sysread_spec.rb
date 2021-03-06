require File.dirname(__FILE__) + '/../../spec_helper'
require "stringio"
require File.dirname(__FILE__) + '/shared/read'

describe "StringIO#sysread" do
  it_behaves_like :stringio_read, :sysread
end

describe "StringIO#sysread when passed [length]" do
  before(:each) do
    @io = StringIO.new("example")
  end
  
  it "raises an EOFError when self's position is at the end" do
    @io.pos = 7
    lambda { @io.sysread(10) }.should raise_error(EOFError)
  end

  ruby_bug "http://redmine.ruby-lang.org/projects/ruby-18/issues/show?id=156", "1.8.7.17" do
    it "returns an empty String when length is 0" do
      @io.sysread(0).should == ""
    end
  end
end