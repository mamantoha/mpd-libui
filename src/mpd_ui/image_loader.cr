module MPDUI
  module ImageLoader
    # Reads the image from *io* using *mime* as the primary hint.
    # Falls back to magic-byte detection via FileType when *mime* is nil or unrecognized.
    # Returns a `StumpyCore::Canvas` or `nil` if the format cannot be determined.
    def self.read(io : IO, mime : String?) : StumpyCore::Canvas?
      case mime
      when "image/jpeg", "image/jpg"
        io.rewind
        return StumpyJPEG.read(io)
      when "image/png"
        io.rewind
        return StumpyPNG.read(io)
      end
      # MIME missing or unrecognised — fall back to magic-byte detection
      read(io)
    end

    # Reads the image from *io* by detecting the format via magic bytes.
    # Returns a `StumpyCore::Canvas` or `nil` if the format is unrecognized.
    def self.read(io : IO) : StumpyCore::Canvas?
      type = FileType.guess(io) # rewinds io
      case type.try(&.mime)
      when "image/jpeg"
        StumpyJPEG.read(io)
      when "image/png"
        StumpyPNG.read(io)
      else
        STDERR.puts "ImageLoader: unrecognized image format#{type.nil? ? " (no magic match)" : ""}"
        nil
      end
    end
  end
end
