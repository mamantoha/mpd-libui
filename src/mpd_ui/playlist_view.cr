module MPDUI
  class PlaylistView
    alias Song = NamedTuple(title: String, artist: String, time: String, active: Bool, id: String)

    @songs : Array(Song) = [] of Song
    @model : UIng::Table::Model?
    @table : UIng::Table?
    @handler : UIng::Table::Model::Handler?
    @box : UIng::Box?
    @on_play : Proc(String, Nil) = ->(id : String) { }

    def widget : UIng::Box
      @box ||= build_widget
    end

    def update(songs : Array(Song)) : Nil
      old_size = @songs.size
      new_size = songs.size
      @songs.clear
      @songs.concat(songs)

      model = @model
      return unless model

      Math.min(old_size, new_size).times { |i| model.row_changed(i) }
      if new_size > old_size
        (old_size...new_size).each { |i| model.row_inserted(i) }
      elsif new_size < old_size
        (new_size...old_size).each { model.row_deleted(new_size) }
      end

      scroll_to_active
    end

    def on_play(&block : String -> Nil) : Nil
      @on_play = block
    end

    # Must be called in window.on_closing BEFORE UIng.quit
    def free : Nil
      if box = @box
        box.delete(0) rescue nil
      end
      @table.try(&.destroy)
      @model.try(&.free)
      @model = nil
      @table = nil
      @handler = nil
    end

    private def scroll_to_active : Nil
      table = @table
      return unless table
      idx = @songs.index(&.[:active])
      return unless idx

      scrolled = UIng::LibUI.control_handle(table.to_unsafe.as(Pointer(UIng::LibUI::Control)))
      tree_view = LibGTK.gtk_bin_get_child(scrolled)
      return if tree_view.null?

      path = LibGTK.gtk_tree_path_new_from_string(idx.to_s)
      return if path.null?
      LibGTK.gtk_tree_view_scroll_to_cell(tree_view, path, Pointer(Void).null, 1, 0.5_f32, 0.0_f32)
      LibGTK.gtk_tree_path_free(path)
    end

    private def build_widget : UIng::Box
      handler = UIng::Table::Model::Handler.new do
        num_columns { 5 }
        column_type do |col|
          col == 4 ? UIng::Table::Value::Type::Color : UIng::Table::Value::Type::String
        end
        num_rows { @songs.size }
        cell_value do |row, col|
          song = @songs[row]?
          next UIng::Table::Value.new("") unless song
          case col
          when 0 then UIng::Table::Value.new(song[:active] ? "▶" : "")
          when 1 then UIng::Table::Value.new(song[:artist])
          when 2 then UIng::Table::Value.new(song[:title])
          when 3 then UIng::Table::Value.new(format_duration(song[:time]))
          when 4
            if song[:active]
              UIng::Table::Value.new(0.18, 0.45, 0.72, 0.4)
            else
              UIng::Table::Value.new(0.0, 0.0, 0.0, 0.0)
            end
          else
            UIng::Table::Value.new("")
          end
        end
        set_cell_value { }
      end

      @handler = handler
      model = UIng::Table::Model.new(handler)
      @model = model

      table = UIng::Table.new(model, 4) do
        append_text_column("", 0, -1)
        append_text_column("Artist", 1, -1)
        append_text_column("Title", 2, -1)
        append_text_column("Time", 3, -1)
      end
      @table = table
      table.column_set_width(0, 20)

      table.on_row_double_clicked do |row|
        if id = @songs[row]?.try(&.[:id])
          @on_play.call(id)
        end
      end

      box = UIng::Box.new(:horizontal, padded: false)
      box.append(table, stretchy: true)
      @box = box
      box
    end

    private def format_duration(seconds : String) : String
      t = seconds.to_i? || 0
      "#{t // 60}:#{(t % 60).to_s.rjust(2, '0')}"
    end
  end
end
