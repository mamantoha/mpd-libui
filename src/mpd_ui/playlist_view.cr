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

    private def build_widget : UIng::Box
      handler = UIng::Table::Model::Handler.new do
        num_columns { 4 }
        column_type do |col|
          col == 3 ? UIng::Table::Value::Type::Color : UIng::Table::Value::Type::String
        end
        num_rows { @songs.size }
        cell_value do |row, col|
          song = @songs[row]?
          next UIng::Table::Value.new("") unless song
          case col
          when 0 then UIng::Table::Value.new(song[:artist])
          when 1 then UIng::Table::Value.new(song[:title])
          when 2 then UIng::Table::Value.new(format_duration(song[:time]))
          when 3
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

      table = UIng::Table.new(model, 3) do
        append_text_column("Artist", 0, -1)
        append_text_column("Title", 1, -1)
        append_text_column("Time", 2, -1)
      end
      @table = table

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
