require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/shared/concat.rb'
require 'strscan'

describe "StringScanner#<<" do
  it_behaves_like(:strscan_concat, :<<)
end
