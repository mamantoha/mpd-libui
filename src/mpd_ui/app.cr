require "uing"

module MPDUI
  class App
    COVER_SIZE    = 120
    WINDOW_TITLE  = "Crystal MPD"
    WINDOW_WIDTH  = 640
    WINDOW_HEIGHT = 600

    @settings : Settings
    @settings_window : SettingsWindow
    @playlist_window : PlaylistView
    @window : UIng::Window?
    @play_pause_button : UIng::Button?
    @title_label : UIng::Label?
    @subtitle_label : UIng::Label?
    @time_label : UIng::Label?
    @seek_slider : UIng::Slider?
    @shuffle_button : ToggleButton?
    @repeat_button : ToggleButton?
    @image_view : UIng::ImageView?
    @blank_image : UIng::Image?
    @cover_image : UIng::Image?
    @current_file : String = ""
    @client : MPD::Client?
    @callback_client : MPD::Client?
    @callback_thread : Thread?
    @elapsed : Float64 = 0.0
    @duration : Float64 = 0.0
    @seeking : Bool = false
    @random : Bool = false
    @repeat : Bool = false

    MEDIA_CONTROL_SYMBOLS = {
      play:        "▶",
      pause:       "⏸",
      stop:        "■",
      prev:        "⏮",
      next:        "⏭",
      shuffle:     "🔀",
      repeat:      "🔁",
      repeat_once: "🔂",
    }

    def initialize
      @settings = Settings.load
      @settings_window = SettingsWindow.new(@settings, -> { reconnect })
      @playlist_window = PlaylistView.new
      @playlist_window.on_play { |id| mpd_action { |c| c.playid(id.to_i) } }
    end

    def run : Nil
      UIng.init
      build_menu
      build_ui
      @window.try(&.show)
      UIng.main
    ensure
      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)
      @blank_image.try(&.free)
      @cover_image.try(&.free)
      UIng.uninit
    end

    private def build_menu : Nil
      UIng::Menu.new("File") do
        append_preferences_item.on_clicked do |_|
          @settings_window.open(@window)
        end
        append_about_item.on_clicked do |w|
          w.msg_box(
            "About Crystal MPD",
            "Crystal MPD v#{VERSION}\nA simple MPD client built with Crystal and UIng."
          )
        end
      end
    end

    private def build_ui : Nil
      window = UIng::Window.new(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, menubar: true, margined: true)

      blank_pixels = Bytes.new(COVER_SIZE * COVER_SIZE * 4) { |i| i % 4 == 3 ? 255_u8 : 80_u8 }
      blank_image = UIng::Image.new(COVER_SIZE, COVER_SIZE)
      blank_image.append(blank_pixels, COVER_SIZE, COVER_SIZE, COVER_SIZE * 4)
      @blank_image = blank_image
      image_view = UIng::ImageView.new(blank_image, :fit)
      img_container = UIng::Box.new(:vertical, padded: false)
      img_container.append(image_view, stretchy: true)
      ic_gtk = UIng::LibUI.control_handle(img_container.to_unsafe.as(Pointer(UIng::LibUI::Control)))
      LibGTK.gtk_widget_set_size_request(ic_gtk, COVER_SIZE, COVER_SIZE)

      prev_button = UIng::Button.new(MEDIA_CONTROL_SYMBOLS[:prev])
      play_pause_button = UIng::Button.new(MEDIA_CONTROL_SYMBOLS[:play])
      next_button = UIng::Button.new(MEDIA_CONTROL_SYMBOLS[:next])

      shuffle_button = ToggleButton.new(MEDIA_CONTROL_SYMBOLS[:shuffle])
      repeat_button = ToggleButton.new(MEDIA_CONTROL_SYMBOLS[:repeat])

      prev_button.on_clicked { mpd_action { |c| c.previous } }
      play_pause_button.on_clicked { toggle_play_pause }
      next_button.on_clicked { mpd_action { |c| c.next } }

      shuffle_button.on_toggled { mpd_action { |c| c.random(shuffle_button.active) } }
      repeat_button.on_toggled { mpd_action { |c| c.repeat(repeat_button.active) } }

      btn_box = UIng::Box.new(:horizontal, padded: true)
      btn_box.append(shuffle_button.area)
      btn_box.append(prev_button)
      btn_box.append(play_pause_button)
      btn_box.append(next_button)
      btn_box.append(repeat_button.area)

      title_label = UIng::Label.new("")
      subtitle_label = UIng::Label.new("")

      info_box = UIng::Box.new(:vertical, padded: false)
      info_box.append(title_label, stretchy: false)
      info_box.append(subtitle_label)

      seek_slider = UIng::Slider.new(0, 100)
      seek_slider.value = 0
      seek_slider.has_tool_tip = false
      time_label = UIng::Label.new("0:00 / 0:00")

      seek_slider.on_changed do |pct|
        # Only update the time label while dragging; suppress timer-driven updates
        @seeking = true
        target = @duration * pct / 100.0
        @time_label.try(&.text = "#{format_time(target)} / #{format_time(@duration)}")
      end

      seek_slider.on_released do |pct|
        @seeking = false
        target = @duration * pct / 100.0
        @elapsed = target
        mpd_action { |c| c.seekcur(target.to_i) }
      end

      progress_row = UIng::Box.new(:horizontal, padded: true)
      progress_row.append(seek_slider, stretchy: true)
      progress_row.append(time_label)

      controls_row = UIng::Box.new(:horizontal, padded: false)
      controls_row.append(UIng::Box.new(:horizontal, padded: false), stretchy: true)
      controls_row.append(btn_box)
      controls_row.append(UIng::Box.new(:horizontal, padded: false), stretchy: true)

      # Right column: info on top, controls in middle, progress at bottom
      right_col = UIng::Box.new(:vertical, padded: true)
      right_col.append(info_box, stretchy: true)
      right_col.append(controls_row)
      right_col.append(progress_row)

      # Header: cover on the left, right column takes remaining space
      header_row = UIng::Box.new(:horizontal, padded: true)
      header_row.append(img_container)
      header_row.append(right_col, stretchy: true)

      root = UIng::Box.new(:vertical, padded: true)
      root.append(header_row)
      root.append(@playlist_window.widget, stretchy: true)

      window.child = root
      window.on_closing do
        @playlist_window.free
        UIng.quit
        true
      end

      @window = window
      @play_pause_button = play_pause_button
      @title_label = title_label
      @subtitle_label = subtitle_label
      @time_label = time_label
      @seek_slider = seek_slider
      @shuffle_button = shuffle_button
      @repeat_button = repeat_button
      @image_view = image_view

      connect

      # Repeating 1-second timer to keep the progress bar moving smoothly
      UIng.timer(1000) do
        update_progress
        1
      end
    end

    private def connect : Nil
      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)

      @client = MPD::Client.new(@settings.host, @settings.port)

      host = @settings.host
      port = @settings.port
      @callback_thread = Thread.new do
        cb = MPD::Client.new(host, port, with_callbacks: true)
        cb.on_callback do |event, state|
          case event
          when .song?
            UIng.queue_main { refresh_status; load_playlist }
          when .state?
            UIng.queue_main { sync_state(state) }
          when .random?
            UIng.queue_main { @random = state == "1"; sync_toggle_buttons }
          when .repeat?
            UIng.queue_main { @repeat = state == "1"; sync_toggle_buttons }
          when .playlist?
            UIng.queue_main { load_playlist }
          when .elapsed?
            elapsed = state.to_f?
            UIng.queue_main { @elapsed = elapsed.not_nil!; update_progress } if elapsed
          end
        end
        @callback_client = cb
        loop { sleep 1.second }
      end

      refresh_status
      load_playlist
    rescue ex
      @title_label.try(&.text = "Connection failed: #{ex.message}")
    end

    private def reconnect : Nil
      connect
    end

    private def toggle_play_pause : Nil
      mpd_action do |client|
        status = client.status
        if status && status["state"]? == "play"
          client.pause(true)
        else
          client.play
        end
      end
    end

    private def refresh_status : Nil
      client = @client
      return unless client

      status = client.status
      song = client.currentsong

      state = status.try(&.fetch("state", "stop")) || "stop"
      @elapsed = status.try(&.[]?("elapsed")).try(&.to_f?) || 0.0
      @duration = status.try(&.[]?("duration")).try(&.to_f?) || 0.0
      @random = status.try(&.[]?("random")) == "1"
      @repeat = status.try(&.[]?("repeat")) == "1"

      @play_pause_button.try(&.text = state == "play" ? MEDIA_CONTROL_SYMBOLS[:pause] : MEDIA_CONTROL_SYMBOLS[:play])
      sync_toggle_buttons

      if song
        file = song["file"]?

        title = song["Title"]? || (file ? File.basename(file, File.extname(file)) : "Unknown")
        artist = song["Artist"]?
        album = song["Album"]?
        subtitle = [artist, album].compact.join(" • ")

        @title_label.try(&.text = title)
        @subtitle_label.try(&.text = subtitle)

        if file && file != @current_file
          @current_file = file
          load_cover_art_async(file)
        end
      else
        @current_file = ""
        @image_view.try(&.image = @blank_image)
        @title_label.try(&.text = state == "stop" ? "Stopped" : "No track")
        @subtitle_label.try(&.text = "")
      end

      update_progress
    rescue ex
      @title_label.try(&.text = "Error: #{ex.message}")
    end

    private def sync_state(state : String) : Nil
      @play_pause_button.try(&.text = state == "play" ? MEDIA_CONTROL_SYMBOLS[:pause] : MEDIA_CONTROL_SYMBOLS[:play])
    end

    private def update_progress : Nil
      return if @seeking

      elapsed = @elapsed
      duration = @duration

      pct = duration > 0 ? ((elapsed / duration) * 100).clamp(0, 100).to_i : 0
      @seek_slider.try(&.value = pct)
      @time_label.try(&.text = "#{format_time(elapsed)} / #{format_time(duration)}")
    end

    private def format_time(seconds : Float64) : String
      t = seconds.to_i
      "#{t // 60}:#{(t % 60).to_s.rjust(2, '0')}"
    end

    private def load_cover_art_async(uri : String) : Nil
      host = @settings.host
      port = @settings.port

      Thread.new do
        begin
          art_client = MPD::Client.new(host, port)

          response = begin
            art_client.readpicture(uri)
          rescue
            nil
          end

          response ||= begin
            art_client.albumart(uri)
          rescue
            nil
          end

          art_client.disconnect

          if response
            meta, io = response
            mime = meta["type"]? || ""

            canvas = case mime
                     when "image/jpeg", "image/jpg"
                       tmp = File.tempfile("mpd_cover", ".jpg")
                       tmp.write(io.to_slice)
                       tmp.flush
                       path = tmp.path
                       tmp.close
                       begin
                         StumpyJPEG.read(path)
                       ensure
                         File.delete(path) rescue nil
                       end
                     when "image/png"
                       tmp = File.tempfile("mpd_cover", ".png")
                       tmp.write(io.to_slice)
                       tmp.flush
                       path = tmp.path
                       tmp.close
                       begin
                         StumpyPNG.read(path)
                       ensure
                         File.delete(path) rescue nil
                       end
                     else
                       STDERR.puts "Cover art: unsupported MIME type #{mime.inspect}"
                       nil
                     end

            if canvas
              width = canvas.width.to_i32
              height = canvas.height.to_i32

              pixels = Bytes.new(width * height * 4)
              (0...height).each do |y|
                (0...width).each do |x|
                  offset = (y * width + x) * 4
                  r, g, b, a = canvas[x, y].to_rgba
                  pixels[offset] = r.to_u8
                  pixels[offset + 1] = g.to_u8
                  pixels[offset + 2] = b.to_u8
                  pixels[offset + 3] = a.to_u8
                end
              end

              image = UIng::Image.new(width, height)
              image.append(pixels, width, height, width * 4)

              UIng.queue_main do
                if @current_file == uri
                  @cover_image.try(&.free)
                  @cover_image = image
                  @image_view.try(&.image = image)
                else
                  image.free
                end
              end
            else
              UIng.queue_main do
                @cover_image.try(&.free)
                @cover_image = nil
                @image_view.try(&.image = @blank_image)
              end
            end
          else
            UIng.queue_main do
              @cover_image.try(&.free)
              @cover_image = nil
              @image_view.try(&.image = @blank_image)
            end
          end
        rescue ex
          STDERR.puts "Cover art error: #{ex.message}"
        end
      end
    end

    private def load_playlist : Nil
      client = @client
      return unless client

      current_id = client.currentsong.try(&.[]?("Id"))
      songs = [] of PlaylistView::Song
      if data = client.playlistinfo
        data.each do |song|
          songs << {
            title:  song["Title"]? || File.basename(song["file"]? || "", File.extname(song["file"]? || "")),
            artist: song["Artist"]? || "",
            time:   song["Time"]? || "0",
            active: song["Id"]? == current_id,
            id:     song["Id"]? || "",
          }
        end
      end
      @playlist_window.update(songs)
    rescue ex
      STDERR.puts "Playlist error: #{ex.message}"
    end

    private def sync_toggle_buttons : Nil
      @shuffle_button.try(&.active = @random)
      @repeat_button.try(&.active = @repeat)
    end

    private def mpd_action(& : MPD::Client -> Nil) : Nil
      client = @client
      return unless client
      yield client
      refresh_status
    rescue ex
      @title_label.try(&.text = "Error: #{ex.message}")
    end
  end
end
