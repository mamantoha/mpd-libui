require "uing"

module MPDUI
  class App
    COVER_SIZE    = 80
    WINDOW_TITLE  = "Crystal MPD"
    WINDOW_WIDTH  = 620
    WINDOW_HEIGHT = 100

    @settings : Settings
    @settings_window : SettingsWindow
    @window : UIng::Window?
    @play_pause_button : UIng::Button?
    @title_label : UIng::Label?
    @subtitle_label : UIng::Label?
    @time_label : UIng::Label?
    @seek_slider : UIng::Slider?
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

    MEDIA_CONTROL_SYMBOLS = {
      play:  "▶",
      pause: "⏸",
      stop:  "■",
      prev:  "⏮",
      next:  "⏭",
    }

    def initialize
      @settings = Settings.load
      @settings_window = SettingsWindow.new(@settings, -> { reconnect })
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

      prev_button = UIng::Button.new(MEDIA_CONTROL_SYMBOLS[:prev])
      play_pause_button = UIng::Button.new(MEDIA_CONTROL_SYMBOLS[:play])
      next_button = UIng::Button.new(MEDIA_CONTROL_SYMBOLS[:next])

      prev_button.on_clicked { mpd_action { |c| c.previous } }
      play_pause_button.on_clicked { toggle_play_pause }
      next_button.on_clicked { mpd_action { |c| c.next } }

      btn_box = UIng::Box.new(:horizontal, padded: true)
      btn_box.append(prev_button)
      btn_box.append(play_pause_button)
      btn_box.append(next_button)

      title_label = UIng::Label.new("")
      subtitle_label = UIng::Label.new("")

      info_box = UIng::Box.new(:vertical, padded: false)
      info_box.append(title_label, stretchy: true)
      info_box.append(subtitle_label)

      main_row = UIng::Box.new(:horizontal, padded: true)
      main_row.append(image_view)
      main_row.append(btn_box)
      main_row.append(info_box, stretchy: true)

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

      root = UIng::Box.new(:vertical, padded: true)
      root.append(main_row, stretchy: true)
      root.append(progress_row)

      window.child = root
      window.on_closing do
        UIng.quit
        true
      end

      @window = window
      @play_pause_button = play_pause_button
      @title_label = title_label
      @subtitle_label = subtitle_label
      @time_label = time_label
      @seek_slider = seek_slider
      @image_view = image_view

      connect
      load_cover_png

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
            UIng.queue_main { refresh_status }
          when .state?
            UIng.queue_main { sync_state(state) }
          when .elapsed?
            elapsed = state.to_f?
            UIng.queue_main { @elapsed = elapsed.not_nil!; update_progress } if elapsed
          end
        end
        @callback_client = cb
        loop { sleep 1.second }
      end

      refresh_status
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

      @play_pause_button.try(&.text = state == "play" ? MEDIA_CONTROL_SYMBOLS[:pause] : MEDIA_CONTROL_SYMBOLS[:play])

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

    private def load_cover_png : Nil
      path = File.join(__DIR__, "..", "..", "cover.png")
      return unless File.exists?(path)

      canvas = StumpyPNG.read(path)
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
      @cover_image.try(&.free)
      @cover_image = image
      @image_view.try(&.image = image)
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
