package body Safe_Frontend.Check_Model is
   function Join
     (Left  : FT.Source_Span;
      Right : FT.Source_Span) return FT.Source_Span
   is
   begin
      return
        (Start_Pos => Left.Start_Pos,
         End_Pos   => Right.End_Pos);
   end Join;

   function Flatten_Name (Expr : Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = Expr_Ident then
         return FT.To_String (Expr.Name);
      elsif Expr.Kind = Expr_Select then
         return Flatten_Name (Expr.Prefix) & "." & FT.To_String (Expr.Selector);
      end if;
      return "";
   end Flatten_Name;

   function Make_Diagnostic
     (Reason             : String;
      Path               : String;
      Span               : FT.Source_Span;
      Message            : String;
      Note               : String := "";
      Suggestion         : String := "";
      Has_Highlight_Span : Boolean := False;
      Highlight_Span     : FT.Source_Span := FT.Null_Span)
      return MD.Diagnostic
   is
      Result : MD.Diagnostic;
   begin
      Result.Reason := FT.To_UString (Reason);
      Result.Path := FT.To_UString (Path);
      Result.Span := Span;
      Result.Message := FT.To_UString (Message);
      Result.Has_Highlight_Span := Has_Highlight_Span;
      Result.Highlight_Span := Highlight_Span;
      if Note'Length > 0 then
         Result.Notes.Append (FT.To_UString (Note));
      end if;
      if Suggestion'Length > 0 then
         Result.Suggestions.Append (FT.To_UString (Suggestion));
      end if;
      return Result;
   end Make_Diagnostic;

   procedure Append_Note
     (Item : in out MD.Diagnostic;
      Note : String) is
   begin
      if Note'Length > 0 then
         Item.Notes.Append (FT.To_UString (Note));
      end if;
   end Append_Note;

   procedure Append_Suggestion
     (Item       : in out MD.Diagnostic;
      Suggestion : String) is
   begin
      if Suggestion'Length > 0 then
         Item.Suggestions.Append (FT.To_UString (Suggestion));
      end if;
   end Append_Suggestion;

   function Unsupported_Source_Construct
     (Path    : String;
      Span    : FT.Source_Span;
      Message : String;
      Note    : String := "") return MD.Diagnostic
   is
   begin
      return
        Make_Diagnostic
          (Reason  => "unsupported_source_construct",
           Path    => Path,
           Span    => Span,
           Message => Message,
           Note    => Note);
   end Unsupported_Source_Construct;

   function Source_Frontend_Error
     (Path    : String;
      Span    : FT.Source_Span;
      Message : String;
      Note    : String := "";
      Suggestion : String := "") return MD.Diagnostic
   is
   begin
      return
        Make_Diagnostic
          (Reason     => "source_frontend_error",
           Path       => Path,
           Span       => Span,
           Message    => Message,
           Note       => Note,
           Suggestion => Suggestion);
   end Source_Frontend_Error;

   function Write_To_Constant
     (Path    : String;
      Span    : FT.Source_Span;
      Message : String) return MD.Diagnostic
   is
   begin
      return
        Make_Diagnostic
          (Reason  => "write_to_constant",
           Path    => Path,
           Span    => Span,
           Message => Message);
   end Write_To_Constant;
end Safe_Frontend.Check_Model;
