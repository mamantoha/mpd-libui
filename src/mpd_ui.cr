require "crystal_mpd"
require "stumpy_png"
require "stumpy_jpeg"
require "./mpd_ui/lib_gtk"
require "./mpd_ui/version"
require "./mpd_ui/settings"
require "./mpd_ui/settings_window"
require "./mpd_ui/file_type"
require "./mpd_ui/image_loader"
require "./mpd_ui/toggle_button"
require "./mpd_ui/playlist_view"
require "./mpd_ui/app"

module MPDUI
  def self.run : Nil
    App.new.run
  end
end

MPDUI.run
