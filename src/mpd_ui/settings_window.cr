module MPDUI
  class SettingsWindow
    WINDOW_WIDTH  = 320
    WINDOW_HEIGHT = 140

    @window : UIng::Window?

    def initialize(@settings : Settings, @on_applied : Proc(Nil))
      @window = nil
    end

    def open(parent : UIng::Window?) : Nil
      if win = @window
        center_on_parent(win, parent)
        win.show
        return
      end

      s = @settings
      win = UIng::Window.new("MPD Connection", WINDOW_WIDTH, WINDOW_HEIGHT, margined: true)
      @window = win

      form = UIng::Form.new(padded: true)

      host_entry = UIng::Entry.new
      host_entry.text = s.host
      port_entry = UIng::Entry.new
      port_entry.text = s.port.to_s

      form.append("Host", host_entry)
      form.append("Port", port_entry)

      apply_btn = UIng::Button.new("Apply")
      apply_btn.on_clicked do
        host = (host_entry.text || "").strip
        port = (port_entry.text || "").strip.to_i?
        s.host = host unless host.empty?
        s.port = port if port
        s.save
        @on_applied.call
        @window = nil
        win.destroy
      end

      vbox = UIng::Box.new(:vertical, padded: true)
      vbox.append(form, stretchy: true)
      vbox.append(apply_btn)
      win.child = vbox
      center_on_parent(win, parent)

      win.on_closing do
        @window = nil
        true
      end
      win.show
    end

    private def center_on_parent(win : UIng::Window, parent : UIng::Window?) : Nil
      return unless parent

      parent_x, parent_y = parent.position
      parent_width, parent_height = parent.content_size
      x = parent_x + (parent_width - WINDOW_WIDTH) // 2
      y = parent_y + (parent_height - WINDOW_HEIGHT) // 2
      win.set_position(x, y)
    rescue
      nil
    end
  end
end
