require File.dirname(__FILE__) + '/../../../spec_helper'
require File.dirname(__FILE__) + '/../../../shared/file/pipe'
require File.dirname(__FILE__) + '/fixtures/classes'

describe "File::Stat#pipe?" do
  it_behaves_like :file_pipe, :pipe?, FileStat, "File::Stat#pipe?"
end

describe "File::Stat#pipe?" do
  it "needs to be reviewed for spec completeness" do
  end
end
