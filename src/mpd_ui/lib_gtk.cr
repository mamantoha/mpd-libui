lib LibGTK
  fun gtk_widget_set_size_request(widget : Pointer(Void), width : LibC::Int, height : LibC::Int) : Void
  fun gtk_bin_get_child(bin : Pointer(Void)) : Pointer(Void)
  fun gtk_tree_path_new_from_string(path : LibC::Char*) : Pointer(Void)
  fun gtk_tree_path_free(path : Pointer(Void)) : Void
  fun gtk_tree_view_scroll_to_cell(tree_view : Pointer(Void), path : Pointer(Void), column : Pointer(Void), use_align : LibC::Int, row_align : LibC::Float, col_align : LibC::Float) : Void
end
