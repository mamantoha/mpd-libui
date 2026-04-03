module MPDUI
  module FileType
    # Describes a detected file type.
    record Type, mime : String, extension : String

    # Number of bytes required to identify any supported type.
    HEADER_SIZE = 8

    private MATCHERS = [
      {Type.new("image/jpeg", "jpg"), Bytes[0xFF, 0xD8, 0xFF]},
      {Type.new("image/png", "png"), Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]},
    ]

    # Guesses the type from the first bytes of *io*.
    # Rewinds *io* before returning so the caller can read the full content.
    def self.guess(io : IO) : Type?
      io.rewind
      header = Bytes.new(HEADER_SIZE)
      io.read_fully?(header)
      io.rewind
      guess(header)
    end

    # Guesses the type from raw *bytes* (e.g. an already-read header buffer).
    def self.guess(bytes : Bytes) : Type?
      MATCHERS.each do |type, magic|
        return type if bytes.size >= magic.size && bytes[0, magic.size] == magic
      end
      nil
    end

    # Returns the MIME type string, or `nil` if unrecognized.
    def self.guess_mime(io : IO) : String?
      guess(io).try(&.mime)
    end

    # Returns the file extension (without dot), or `nil` if unrecognized.
    def self.guess_extension(io : IO) : String?
      guess(io).try(&.extension)
    end

    # Returns `true` if the content is a recognized image type.
    def self.image?(io : IO) : Bool
      !guess(io).nil?
    end
  end
end
