module MPDUI
  # A custom toggle button built on UIng::Area.
  # Renders as a fixed-size rounded rect with a centered emoji/text label.
  # Active state is indicated by a highlighted background.
  class ToggleButton
    SIZE = 36

    # bg colors (r,g,b,a)
    BG_NORMAL = {0.22, 0.22, 0.22, 1.0}
    BG_ACTIVE = {0.18, 0.45, 0.72, 1.0}
    BG_HOVER  = {0.30, 0.30, 0.30, 1.0}
    BORDER    = {0.45, 0.45, 0.45, 1.0}

    getter area : UIng::Area
    getter active : Bool = false

    @handler : UIng::Area::Handler
    @label : String
    @hover : Bool = false
    @on_toggled : Proc(Bool, Nil) = ->(b : Bool) { }
    @font : UIng::FontDescriptor

    def initialize(@label : String, active : Bool = false)
      @active = active
      @handler = UIng::Area::Handler.new
      @font = UIng::FontDescriptor.new(family: nil) # loads system control font

      @handler.draw do |_area, params|
        draw(params)
      end

      @handler.mouse_event do |_area, event|
        if event.down == 1
          @active = !@active
          _area.queue_redraw_all
          @on_toggled.call(@active)
        end
      end

      @handler.mouse_crossed do |_area, left|
        @hover = !left
        _area.queue_redraw_all
      end

      @area = UIng::Area.new(@handler)
      gtk_widget = UIng::LibUI.control_handle(@area.to_unsafe.as(Pointer(UIng::LibUI::Control)))
      LibGTK.gtk_widget_set_size_request(gtk_widget, SIZE, SIZE)
    end

    def active=(value : Bool)
      @active = value
      @area.queue_redraw_all
    end

    def on_toggled(&block : Bool -> Nil)
      @on_toggled = block
    end

    private def draw(params : UIng::Area::Draw::Params) : Nil
      ctx = params.context
      w = params.area_width
      h = params.area_height
      return if w < 1.0 || h < 1.0

      bg = @active ? BG_ACTIVE : (@hover ? BG_HOVER : BG_NORMAL)

      # filled background (simple rectangle — no rounded-rect primitive in libui)
      bg_brush = UIng::Area::Draw::Brush.new(:solid, *bg)
      ctx.fill_path(bg_brush) do |path|
        path.add_rectangle(0.0, 0.0, w, h)
      end

      # border
      border_brush = UIng::Area::Draw::Brush.new(:solid, *BORDER)
      stroke = UIng::Area::Draw::StrokeParams.new(
        cap: :flat, join: :miter, thickness: 1.0, miter_limit: 10.0
      )
      ctx.stroke_path(border_brush, stroke) do |path|
        path.add_rectangle(0.5, 0.5, w - 1.0, h - 1.0)
      end

      # centered label text — white so it's visible on dark bg
      len = LibC::SizeT.new(@label.bytesize)
      UIng::Area::AttributedString.open(@label) do |astr|
        astr.set_attribute(UIng::Area::Attribute.new_color(1.0, 1.0, 1.0, 1.0), LibC::SizeT.new(0), len)
        UIng::Area::Draw::TextLayout.open(astr, @font, w, :center) do |layout|
          _, text_h = layout.extents
          ctx.draw_text_layout(layout, 0.0, (h - text_h) / 2.0)
        end
      end
    end
  end
end
