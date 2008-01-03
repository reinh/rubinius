def with_timezone(name, offset = nil, daylight_saving_zone = "")
  zone = name.dup

  if (offset)
    # TZ convention is backwards
    offset = -offset

    zone << offset.to_s
    zone << ":00:00"
  end
  zone << daylight_saving_zone

  old = ENV["TZ"]
  ENV["TZ"] = zone

  begin
    yield
  ensure
    ENV["TZ"] = old
  end
end

def localtime(seconds)
  platform_is :os => [:darwin, :bsd] do
    return `date -r #{seconds} +'%a %b %d %H:%M:%S %z %Y'`.chomp
  end
  
  platform_is :os => :linux do
    return `date -d @#{seconds} +'%a %b %d %H:%M:%S %z %Y'`.chomp
  end
  
  return `date -j -f "%s" #{seconds} "+%a %b %d %H:%M:%S %z %Y"`.chomp
end