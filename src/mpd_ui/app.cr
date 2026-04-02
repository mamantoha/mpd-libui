require "uing"

module MPDUI
  class App
    WINDOW_TITLE  = "Crystal MPD"
    WINDOW_WIDTH  = 420
    WINDOW_HEIGHT = 120

    @settings : Settings
    @settings_window : SettingsWindow
    @window : UIng::Window?
    @play_pause_button : UIng::Button?
    @track_label : UIng::Label?
    @client : MPD::Client?
    @callback_client : MPD::Client?
    @callback_thread : Thread?

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

      track_label = UIng::Label.new("Not connected")

      prev_button = UIng::Button.new("Prev")
      play_pause_button = UIng::Button.new("Play")
      next_button = UIng::Button.new("Next")

      prev_button.on_clicked { mpd_action { |c| c.previous } }
      play_pause_button.on_clicked { toggle_play_pause }
      next_button.on_clicked { mpd_action { |c| c.next } }

      controls = UIng::Box.new(:horizontal, padded: true)
      controls.append(prev_button)
      controls.append(play_pause_button)
      controls.append(next_button)

      root = UIng::Box.new(:vertical, padded: true)
      root.append(track_label)
      root.append(controls)

      window.child = root
      window.on_closing do
        UIng.quit
        true
      end

      @window = window
      @play_pause_button = play_pause_button
      @track_label = track_label

      connect
    end

    private def connect : Nil
      @client.try(&.disconnect)
      @callback_client.try(&.disconnect)

      # Command client - used only from the UIng main thread
      @client = MPD::Client.new(@settings.host, @settings.port)

      # Callback client - lives on its own thread so its fiber scheduler
      # can run independently of UIng.main blocking the main thread
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
          end
        end
        @callback_client = cb
        # Keep thread alive; sleep yields to the fiber scheduler so the
        # polling fiber spawned by with_callbacks can run between sleeps
        loop { sleep 1.second }
      end

      refresh_status
    rescue ex
      @track_label.try(&.text = "Connection failed: #{ex.message}")
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
      @play_pause_button.try(&.text = state == "play" ? "Pause" : "Play")

      if song
        title = song["Title"]? || song["file"]? || "Unknown"
        artist = song["Artist"]?
        label = artist ? "#{artist} - #{title}" : title
        @track_label.try(&.text = label)
      else
        @track_label.try(&.text = state == "stop" ? "Stopped" : "No track")
      end
    rescue ex
      @track_label.try(&.text = "Error: #{ex.message}")
    end

    private def sync_state(state : String) : Nil
      @play_pause_button.try(&.text = state == "play" ? "Pause" : "Play")
    end

    private def mpd_action(& : MPD::Client -> Nil) : Nil
      client = @client
      return unless client
      yield client
      refresh_status
    rescue ex
      @track_label.try(&.text = "Error: #{ex.message}")
    end
  end
end
