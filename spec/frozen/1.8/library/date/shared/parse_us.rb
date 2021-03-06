shared :date_parse_us do |sep|
  describe "Date#parse(#{sep})" do
    it "parses a YYYY#{sep}MM#{sep}DD string into a Date object" do
      d = Date.parse("2007#{sep}10#{sep}01")
      d.year.should  == 2007
      d.month.should == 10
      d.day.should   == 1
    end

    it "parses a MM#{sep}DD#{sep}YYYY string into a Date object" do
      d = Date.parse("10#{sep}01#{sep}2007")
      d.year.should  == 2007
      d.month.should == 10
      d.day.should   == 1
    end

    it "parses a MM#{sep}DD#{sep}YY string into a Date object" do
      d = Date.parse("10#{sep}01#{sep}07")
      d.year.should  == 7
      d.month.should == 10
      d.day.should   == 1
    end

    it "parses a MM#{sep}DD#{sep}YY string into a Date object using the year digits as 20XX" do
      d = Date.parse("10#{sep}01#{sep}07", true)
      d.year.should  == 2007
      d.month.should == 10
      d.day.should   == 1
    end
  end
end