with Safe_Frontend.Name_Utils;

package body Safe_Frontend.Ada_Emit.Internal is
   package FNU renames Safe_Frontend.Name_Utils;

   use SU;
   use type Ada.Containers.Count_Type;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type FT.Source_Span;

   Indent_Width : constant Positive := 3;

   procedure Raise_Internal (Message : String) is
   begin
      raise Emitter_Internal with Message;
   end Raise_Internal;

   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String)
   is
   begin
      State.Unsupported_Span := Span;
      State.Unsupported_Message := FT.To_UString (Message);
      raise Emitter_Unsupported;
   end Raise_Unsupported;

   function Has_Text (Item : FT.UString) return Boolean is
   begin
      return FT.To_String (Item)'Length > 0;
   end Has_Text;

   function Trim_Image (Value : Long_Long_Integer) return String is
      Image : constant String := Long_Long_Integer'Image (Value);
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim_Image;

   function Trim_Wide_Image (Value : CM.Wide_Integer) return String is
      Image : constant String := CM.Wide_Integer'Image (Value);
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim_Wide_Image;

   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean is
   begin
      return FT.To_String (Info.Kind) = "access";
   end Is_Access_Type;

   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Is_Access_Type (Info)
        and then FT.To_String (Info.Access_Role) = "Owner";
   end Is_Owner_Access;

   function Sanitized_Helper_Name (Name : String) return String is
      Result : SU.Unbounded_String;
   begin
      for Ch of Name loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := Result & SU.To_Unbounded_String ((1 => Ch));
         else
            Result := Result & SU.To_Unbounded_String ("_");
         end if;
      end loop;
      return SU.To_String (Result);
   end Sanitized_Helper_Name;

   function Indentation (Depth : Natural) return String is
   begin
      if Depth = 0 then
         return "";
      end if;
      return (1 .. Depth * Indent_Width => ' ');
   end Indentation;

   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0) is
   begin
      Buffer :=
        Buffer
        & SU.To_Unbounded_String (Indentation (Depth) & Text & ASCII.LF);
   end Append_Line;

   procedure Append_Source_Comment
     (Buffer      : in out SU.Unbounded_String;
      Source_File : String;
      Span        : FT.Source_Span;
      Depth       : Natural := 0) is
   begin
      if Span = FT.Null_Span then
         return;
      end if;

      Append_Line
        (Buffer,
         "-- safe:"
         & Source_File
         & ":"
         & FT.Image (Span.Start_Pos.Line)
         & ":"
         & FT.Image (Span.Start_Pos.Column),
         Depth);
   end Append_Source_Comment;

   function Join_Names (Items : FT.UString_Vectors.Vector) return String is
      Result : SU.Unbounded_String;
      First  : Boolean := True;
   begin
      for Item of Items loop
         if not First then
            Result := Result & SU.To_Unbounded_String (", ");
         else
            First := False;
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Item));
      end loop;
      return SU.To_String (Result);
   end Join_Names;

   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean is
   begin
      for Item of Items loop
         if FT.To_String (Item) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Name;

   function Starts_With
     (Text   : String;
      Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Root_Name (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return FT.To_String (Expr.Name);
         when CM.Expr_Select | CM.Expr_Resolved_Index =>
            return Root_Name (Expr.Prefix);
         when CM.Expr_Annotated =>
            return Root_Name (Expr.Inner);
         when CM.Expr_Unknown
            | CM.Expr_Int
            | CM.Expr_Real
            | CM.Expr_String
            | CM.Expr_Bool
            | CM.Expr_Enum_Literal
            | CM.Expr_Null
            | CM.Expr_Apply
            | CM.Expr_Conversion
            | CM.Expr_Call
            | CM.Expr_Allocator
            | CM.Expr_Aggregate
            | CM.Expr_Array_Literal
            | CM.Expr_Tuple
            | CM.Expr_Some
            | CM.Expr_None
            | CM.Expr_Try
            | CM.Expr_Unary
            | CM.Expr_Binary
            | CM.Expr_Subtype_Indication =>
            return "";
      end case;
   end Root_Name;

   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl
   is
   begin
      for Item of Unit.Channels loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      for Item of Unit.Imported_Channels loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Lookup_Channel;

   function Canonical_Name (Value : String) return String is
   begin
      return FT.Lowercase (Value);
   end Canonical_Name;

   function Sanitize_Type_Name_Component (Value : String) return String
     renames FNU.Sanitize_Type_Name_Component;

   function Shared_Wrapper_Object_Name
     (Root_Name : String) return String
   is
   begin
      return
        "Safe_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Wrapper_Object_Name;

   function Shared_Wrapper_Type_Name
     (Root_Name : String) return String
   is
   begin
      return Shared_Wrapper_Object_Name (Root_Name) & "_Wrapper";
   end Shared_Wrapper_Type_Name;

   function Shared_Public_Helper_Base_Name
     (Root_Name : String) return String
   is
   begin
      return
        "Safe_Public_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Public_Helper_Base_Name;

   function Shared_Public_Helper_Name
     (Root_Name : String;
      Operation : String) return String
   is
   begin
      return Shared_Public_Helper_Base_Name (Root_Name) & "_" & Operation;
   end Shared_Public_Helper_Name;

   function Shared_Get_All_Name return String is
   begin
      return "Get_All";
   end Shared_Get_All_Name;

   function Shared_Set_All_Name return String is
   begin
      return "Set_All";
   end Shared_Set_All_Name;

   function Shared_Get_Length_Name return String is
   begin
      return "Get_Length";
   end Shared_Get_Length_Name;

   function Shared_Append_Name return String is
   begin
      return "Append";
   end Shared_Append_Name;

   function Shared_Pop_Last_Name return String is
   begin
      return "Pop_Last";
   end Shared_Pop_Last_Name;

   function Shared_Contains_Name return String is
   begin
      return "Contains";
   end Shared_Contains_Name;

   function Shared_Get_Name return String is
   begin
      return "Get";
   end Shared_Get_Name;

   function Shared_Set_Name return String is
   begin
      return "Set";
   end Shared_Set_Name;

   function Shared_Remove_Name return String is
   begin
      return "Remove";
   end Shared_Remove_Name;

   function Shared_Field_Getter_Name
     (Field_Name : String) return String
   is
   begin
      return
        "Get_" & Sanitize_Type_Name_Component (Canonical_Name (Field_Name));
   end Shared_Field_Getter_Name;

   function Shared_Field_Setter_Name
     (Field_Name : String) return String
   is
   begin
      return
        "Set_" & Sanitize_Type_Name_Component (Canonical_Name (Field_Name));
   end Shared_Field_Setter_Name;

   function Shared_Nested_Field_Setter_Name
     (Path_Names : FT.UString_Vectors.Vector) return String
   is
      Result : FT.UString := FT.To_UString ("Set_Path");
   begin
      for Name of Path_Names loop
         Result :=
           FT.To_UString
             (FT.To_String (Result)
              & "_"
              & Sanitize_Type_Name_Component
                  (Canonical_Name (FT.To_String (Name))));
      end loop;
      return FT.To_String (Result);
   end Shared_Nested_Field_Setter_Name;

   procedure Add_Wide_Name
     (State : in out Emit_State;
      Name  : String) is
   begin
      if Name'Length = 0 or else Contains_Name (State.Wide_Local_Names, Name) then
         return;
      end if;
      State.Wide_Local_Names.Append (FT.To_UString (Name));
   end Add_Wide_Name;

   function Is_Wide_Name
     (State : Emit_State;
      Name  : String) return Boolean is
   begin
      return Name'Length > 0 and then Contains_Name (State.Wide_Local_Names, Name);
   end Is_Wide_Name;

   function Names_Use_Wide_Storage
     (State : Emit_State;
      Names : FT.UString_Vectors.Vector) return Boolean is
   begin
      for Name of Names loop
         if Is_Wide_Name (State, FT.To_String (Name)) then
            return True;
         end if;
      end loop;
      return False;
   end Names_Use_Wide_Storage;

   procedure Restore_Wide_Names
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) is
   begin
      while State.Wide_Local_Names.Length > Previous_Length loop
         State.Wide_Local_Names.Delete_Last;
      end loop;
   end Restore_Wide_Names;

   procedure Bind_Static_Length
     (State  : in out Emit_State;
      Name   : String;
      Length : Natural) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Static_Length_Bindings.Append
        ((Name => FT.To_UString (Name), Known => True, Length => Length));
   end Bind_Static_Length;

   function Static_Binding_Name_Matches
     (Binding_Name : String;
      Query_Name   : String) return Boolean
   is
      function Has_Dot (Name : String) return Boolean is
      begin
         for Ch of Name loop
            if Ch = '.' then
               return True;
            end if;
         end loop;
         return False;
      end Has_Dot;

      function Has_Qualified_Suffix
        (Qualified_Name : String;
         Bare_Name      : String) return Boolean is
      begin
         return Bare_Name'Length > 0
           and then Qualified_Name'Length > Bare_Name'Length
           and then Qualified_Name (Qualified_Name'Last - Bare_Name'Length + 1 .. Qualified_Name'Last) = Bare_Name
           and then Qualified_Name (Qualified_Name'Last - Bare_Name'Length) = '.';
      end Has_Qualified_Suffix;
   begin
      return Binding_Name = Query_Name
        or else (not Has_Dot (Query_Name) and then Has_Qualified_Suffix (Binding_Name, Query_Name))
        or else (not Has_Dot (Binding_Name) and then Has_Qualified_Suffix (Query_Name, Binding_Name));
   end Static_Binding_Name_Matches;

   function Try_Static_Length
     (State  : Emit_State;
      Name   : String;
      Length : out Natural) return Boolean is
   begin
      if Name'Length = 0 or else State.Static_Length_Bindings.Is_Empty then
         return False;
      end if;

      for Index in reverse State.Static_Length_Bindings.First_Index .. State.Static_Length_Bindings.Last_Index loop
         declare
            Binding : constant Static_Length_Binding := State.Static_Length_Bindings (Index);
         begin
            if Static_Binding_Name_Matches (FT.To_String (Binding.Name), Name) then
               if Binding.Known then
                  Length := Binding.Length;
                  return True;
               end if;
               return False;
            end if;
         end;
      end loop;

      return False;
   end Try_Static_Length;

   procedure Restore_Static_Length_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) is
   begin
      while State.Static_Length_Bindings.Length > Previous_Length loop
         State.Static_Length_Bindings.Delete_Last;
      end loop;
   end Restore_Static_Length_Bindings;

   procedure Invalidate_Static_Length
     (State : in out Emit_State;
      Name  : String) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Static_Length_Bindings.Append
        ((Name => FT.To_UString (Name), Known => False, Length => 0));
   end Invalidate_Static_Length;

   procedure Bind_Static_Integer
     (State : in out Emit_State;
      Name  : String;
      Value : Long_Long_Integer) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Static_Integer_Bindings.Append
        ((Name => FT.To_UString (Name), Known => True, Value => Value));
   end Bind_Static_Integer;

   procedure Invalidate_Static_Integer
     (State : in out Emit_State;
      Name  : String) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Static_Integer_Bindings.Append
        ((Name => FT.To_UString (Name), Known => False, Value => 0));
   end Invalidate_Static_Integer;

   procedure Bind_Loop_Integer
     (State : in out Emit_State;
      Name  : String;
      Value : Long_Long_Integer) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Loop_Integer_Bindings.Append
        ((Name => FT.To_UString (Name), Known => True, Value => Value));
   end Bind_Loop_Integer;

   procedure Invalidate_Loop_Integer
     (State : in out Emit_State;
      Name  : String) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Loop_Integer_Bindings.Append
        ((Name => FT.To_UString (Name), Known => False, Value => 0));
   end Invalidate_Loop_Integer;

   procedure Bind_Static_String
     (State : in out Emit_State;
      Name  : String;
      Image : String) is
   begin
      if Name'Length = 0 then
         return;
      end if;
      State.Static_String_Bindings.Append
        ((Name => FT.To_UString (Name),
          Image => FT.To_UString (Image)));
   end Bind_Static_String;

   function Has_Static_Integer_Tracking
     (State : Emit_State;
      Name  : String) return Boolean is
   begin
      if Name'Length = 0 or else State.Static_Integer_Bindings.Is_Empty then
         return False;
      end if;

      for Binding of State.Static_Integer_Bindings loop
         if Static_Binding_Name_Matches (FT.To_String (Binding.Name), Name) then
            return True;
         end if;
      end loop;

      return False;
   end Has_Static_Integer_Tracking;

   function Try_Static_Integer_Binding
     (State : Emit_State;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean is
   begin
      Value := 0;
      if Name'Length = 0 or else State.Static_Integer_Bindings.Is_Empty then
         return False;
      end if;

      for Index in reverse State.Static_Integer_Bindings.First_Index .. State.Static_Integer_Bindings.Last_Index loop
         declare
            Binding : constant Static_Integer_Binding := State.Static_Integer_Bindings (Index);
         begin
            if Static_Binding_Name_Matches (FT.To_String (Binding.Name), Name) then
               if Binding.Known then
                  Value := Binding.Value;
                  return True;
               end if;
               return False;
            end if;
         end;
      end loop;

      return False;
   end Try_Static_Integer_Binding;

   function Has_Loop_Integer_Tracking
     (State : Emit_State;
      Name  : String) return Boolean is
   begin
      if Name'Length = 0 or else State.Loop_Integer_Bindings.Is_Empty then
         return False;
      end if;

      for Binding of State.Loop_Integer_Bindings loop
         if Static_Binding_Name_Matches (FT.To_String (Binding.Name), Name) then
            return True;
         end if;
      end loop;

      return False;
   end Has_Loop_Integer_Tracking;

   function Try_Loop_Integer_Binding
     (State : Emit_State;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean is
   begin
      Value := 0;
      if Name'Length = 0 or else State.Loop_Integer_Bindings.Is_Empty then
         return False;
      end if;

      for Index in reverse State.Loop_Integer_Bindings.First_Index .. State.Loop_Integer_Bindings.Last_Index loop
         declare
            Binding : constant Static_Integer_Binding := State.Loop_Integer_Bindings (Index);
         begin
            if Static_Binding_Name_Matches (FT.To_String (Binding.Name), Name) then
               if Binding.Known then
                  Value := Binding.Value;
                  return True;
               end if;
               return False;
            end if;
         end;
      end loop;

      return False;
   end Try_Loop_Integer_Binding;

   function Try_Static_String_Binding
     (State : Emit_State;
      Name  : String;
      Image : out SU.Unbounded_String) return Boolean is
   begin
      Image := SU.Null_Unbounded_String;
      if Name'Length = 0 or else State.Static_String_Bindings.Is_Empty then
         return False;
      end if;

      for Index in reverse State.Static_String_Bindings.First_Index .. State.Static_String_Bindings.Last_Index loop
         declare
            Binding : constant Static_String_Binding := State.Static_String_Bindings (Index);
         begin
            if FT.To_String (Binding.Name) = Name then
               Image := SU.To_Unbounded_String (FT.To_String (Binding.Image));
               return True;
            end if;
         end;
      end loop;

      return False;
   end Try_Static_String_Binding;

   procedure Restore_Static_Integer_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) is
   begin
      while State.Static_Integer_Bindings.Length > Previous_Length loop
         State.Static_Integer_Bindings.Delete_Last;
      end loop;
   end Restore_Static_Integer_Bindings;

   procedure Restore_Loop_Integer_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) is
   begin
      while State.Loop_Integer_Bindings.Length > Previous_Length loop
         State.Loop_Integer_Bindings.Delete_Last;
      end loop;
   end Restore_Loop_Integer_Bindings;

   procedure Restore_Static_String_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) is
   begin
      while State.Static_String_Bindings.Length > Previous_Length loop
         State.Static_String_Bindings.Delete_Last;
      end loop;
   end Restore_Static_String_Bindings;

   procedure Clear_All_Static_Bindings (State : in out Emit_State) is
   begin
      Restore_Static_Length_Bindings (State, 0);
      Restore_Static_Integer_Bindings (State, 0);
      Restore_Loop_Integer_Bindings (State, 0);
      Restore_Static_String_Bindings (State, 0);
   end Clear_All_Static_Bindings;

   procedure Push_Type_Binding_Frame (State : in out Emit_State) is
   begin
      State.Type_Binding_Stack.Append ((Bindings => <>));
   end Push_Type_Binding_Frame;

   procedure Pop_Type_Binding_Frame (State : in out Emit_State) is
   begin
      if State.Type_Binding_Stack.Is_Empty then
         Raise_Internal ("type binding frame stack underflow during Ada emission");
      end if;
      State.Type_Binding_Stack.Delete_Last;
   end Pop_Type_Binding_Frame;

   procedure Add_Type_Binding
     (State     : in out Emit_State;
      Name      : String;
      Type_Info : GM.Type_Descriptor;
      Is_Constant : Boolean := False) is
   begin
      if State.Type_Binding_Stack.Is_Empty then
         Raise_Internal ("type binding added outside an active binding scope during Ada emission");
      end if;

      declare
         Frame : Type_Binding_Frame := State.Type_Binding_Stack.Last_Element;
      begin
         Frame.Bindings.Append
           ((Name      => FT.To_UString (Name),
             Type_Info => Type_Info,
             Is_Constant => Is_Constant));
         State.Type_Binding_Stack.Replace_Element (State.Type_Binding_Stack.Last_Index, Frame);
      end;
   end Add_Type_Binding;

   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         for Name of Decl.Names loop
            Add_Type_Binding
              (State, FT.To_String (Name), Decl.Type_Info, Decl.Is_Constant);
         end loop;
      end loop;
   end Register_Type_Bindings;

   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         for Name of Decl.Names loop
            Add_Type_Binding
              (State, FT.To_String (Name), Decl.Type_Info, Decl.Is_Constant);
         end loop;
      end loop;
   end Register_Type_Bindings;

   procedure Register_Param_Type_Bindings
     (State  : in out Emit_State;
      Params : CM.Symbol_Vectors.Vector) is
   begin
      for Param of Params loop
         Add_Type_Binding (State, FT.To_String (Param.Name), Param.Type_Info);
      end loop;
   end Register_Param_Type_Bindings;

   function Lookup_Bound_Type
     (State     : Emit_State;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean is
   begin
      if Name'Length = 0 or else State.Type_Binding_Stack.Is_Empty then
         return False;
      end if;

      for Frame_Index in reverse State.Type_Binding_Stack.First_Index .. State.Type_Binding_Stack.Last_Index loop
         declare
            Frame : constant Type_Binding_Frame := State.Type_Binding_Stack (Frame_Index);
         begin
            if not Frame.Bindings.Is_Empty then
               for Binding_Index in reverse Frame.Bindings.First_Index .. Frame.Bindings.Last_Index loop
                  declare
                     Binding : constant Type_Binding := Frame.Bindings (Binding_Index);
                  begin
                     if FT.To_String (Binding.Name) = Name then
                        Type_Info := Binding.Type_Info;
                        return True;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      return False;
   end Lookup_Bound_Type;

   function Lookup_Bound_Is_Constant
     (State : Emit_State;
      Name  : String) return Boolean is
   begin
      if Name'Length = 0 or else State.Type_Binding_Stack.Is_Empty then
         return False;
      end if;

      for Frame_Index in reverse State.Type_Binding_Stack.First_Index .. State.Type_Binding_Stack.Last_Index loop
         declare
            Frame : constant Type_Binding_Frame := State.Type_Binding_Stack (Frame_Index);
         begin
            if not Frame.Bindings.Is_Empty then
               for Binding_Index in reverse Frame.Bindings.First_Index .. Frame.Bindings.Last_Index loop
                  declare
                     Binding : constant Type_Binding := Frame.Bindings (Binding_Index);
                  begin
                     if FT.To_String (Binding.Name) = Name then
                        return Binding.Is_Constant;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;

      return False;
   end Lookup_Bound_Is_Constant;

   procedure Push_Cleanup_Frame (State : in out Emit_State) is
   begin
      State.Cleanup_Stack.Append ((Items => <>));
   end Push_Cleanup_Frame;

   procedure Pop_Cleanup_Frame (State : in out Emit_State) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         Raise_Internal ("cleanup frame stack underflow during Ada emission");
      end if;
      State.Cleanup_Stack.Delete_Last;
   end Pop_Cleanup_Frame;

   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
      Free_Proc : String := "";
      Is_Constant : Boolean := False;
      Always_Terminates_Suppression_OK : Boolean := False;
      Action    : Cleanup_Action := Cleanup_Deallocate) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         Raise_Internal ("cleanup item added outside an active cleanup scope during Ada emission");
      end if;

      declare
         Frame : Cleanup_Frame := State.Cleanup_Stack.Last_Element;
      begin
         Frame.Items.Append
           ((Action    => Action,
             Name      => FT.To_UString (Name),
             Type_Name => FT.To_UString (Type_Name),
             Free_Proc => FT.To_UString (Free_Proc),
             Is_Constant => Is_Constant,
             Always_Terminates_Suppression_OK =>
               Always_Terminates_Suppression_OK));
         State.Cleanup_Stack.Replace_Element (State.Cleanup_Stack.Last_Index, Frame);
      end;
   end Add_Cleanup_Item;

   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         if Is_Owner_Access (Decl.Type_Info) then
            for Name of Decl.Names loop
               Add_Cleanup_Item
                 (State,
                  FT.To_String (Name),
                  FT.To_String (Decl.Type_Info.Name),
                  Is_Constant => False);
            end loop;
         end if;
      end loop;
   end Register_Cleanup_Items;

   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         if Is_Owner_Access (Decl.Type_Info) then
            for Name of Decl.Names loop
               Add_Cleanup_Item
                 (State,
                  FT.To_String (Name),
                  FT.To_String (Decl.Type_Info.Name),
                  Is_Constant => False);
            end loop;
         end if;
      end loop;
   end Register_Cleanup_Items;

   Local_Warning_Suppressions : constant Warning_Suppression_Array :=
     (1 =>
        (Pattern => FT.To_UString ("is set by"),
         Reason  => FT.To_UString ("generated local cleanup is intentional")),
      2 =>
        (Pattern => FT.To_UString ("unused initial value of"),
         Reason  => FT.To_UString ("generated local cleanup is intentional")),
      3 =>
        (Pattern => FT.To_UString ("unused assignment"),
         Reason  => FT.To_UString ("generated local cleanup is intentional")),
      4 =>
        (Pattern => FT.To_UString ("initialization of"),
         Reason  => FT.To_UString ("generated local cleanup is intentional")),
      5 =>
        (Pattern => FT.To_UString ("statement has no effect"),
         Reason  => FT.To_UString ("generated local cleanup is intentional")));

   Local_Warning_Restores : constant Warning_Restore_Array :=
     (1 => FT.To_UString ("statement has no effect"),
      2 => FT.To_UString ("unused assignment"),
      3 => FT.To_UString ("unused initial value of"),
      4 => FT.To_UString ("initialization of"),
      5 => FT.To_UString ("is set by"));

   Initialization_Warning_Suppressions : constant Warning_Suppression_Array :=
     (1 =>
        (Pattern => FT.To_UString ("initialization of"),
         Reason  => FT.To_UString ("generated local initialization is intentional")));

   Initialization_Warning_Restores : constant Warning_Restore_Array :=
     (1 => FT.To_UString ("initialization of"));

   Channel_Staged_Call_Warning_Suppressions : constant Warning_Suppression_Array :=
     (1 =>
        (Pattern => FT.To_UString ("is set by"),
         Reason  => FT.To_UString ("heap-backed channel staging is intentional")));

   Channel_Staged_Call_Warning_Restores : constant Warning_Restore_Array :=
     (1 => FT.To_UString ("is set by"));

   Task_Assignment_Warning_Suppressions : constant Warning_Suppression_Array :=
     (1 =>
        (Pattern => FT.To_UString ("statement has no effect"),
         Reason  => FT.To_UString ("task-local state updates are intentionally isolated")),
      2 =>
        (Pattern => FT.To_UString ("unused assignment"),
         Reason  => FT.To_UString ("task-local state updates are intentionally isolated")));

   Task_Assignment_Warning_Restores : constant Warning_Restore_Array :=
     (1 => FT.To_UString ("unused assignment"),
      2 => FT.To_UString ("statement has no effect"));

   Task_If_Warning_Suppressions : constant Warning_Suppression_Array :=
     (1 =>
        (Pattern => FT.To_UString ("statement has no effect"),
         Reason  => FT.To_UString ("task-local branching is intentionally isolated")));

   Task_If_Warning_Restores : constant Warning_Restore_Array :=
     (1 => FT.To_UString ("statement has no effect"));

   Task_Channel_Call_Warning_Suppressions : constant Warning_Suppression_Array :=
     (1 =>
        (Pattern => FT.To_UString ("is set by"),
         Reason  => FT.To_UString ("channel results are consumed on the success path only")));

   Task_Channel_Call_Warning_Restores : constant Warning_Restore_Array :=
     (1 => FT.To_UString ("is set by"));

   procedure Append_Gnatprove_Warning_Suppression
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Reason  : String;
      Depth   : Natural) is
   begin
      Append_Line
        (Buffer,
         "pragma Warnings (GNATprove, Off, """
         & Pattern
         & """, Reason => """
         & Reason
         & """);",
         Depth);
   end Append_Gnatprove_Warning_Suppression;

   procedure Append_Gnatprove_Warning_Restore
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Depth   : Natural) is
   begin
      Append_Line
        (Buffer,
         "pragma Warnings (GNATprove, On, """ & Pattern & """);",
         Depth);
   end Append_Gnatprove_Warning_Restore;

   procedure Append_Gnatprove_Warning_Suppressions
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Suppression_Array;
      Depth    : Natural) is
   begin
      for Warning of Warnings loop
         Append_Gnatprove_Warning_Suppression
           (Buffer,
            FT.To_String (Warning.Pattern),
            FT.To_String (Warning.Reason),
            Depth);
      end loop;
   end Append_Gnatprove_Warning_Suppressions;

   procedure Append_Gnatprove_Warning_Restores
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Restore_Array;
      Depth    : Natural) is
   begin
      for Warning of Warnings loop
         Append_Gnatprove_Warning_Restore
           (Buffer,
            FT.To_String (Warning),
            Depth);
      end loop;
   end Append_Gnatprove_Warning_Restores;

   procedure Append_Local_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Suppressions
        (Buffer, Local_Warning_Suppressions, Depth);
   end Append_Local_Warning_Suppression;

   procedure Append_Local_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Restores
        (Buffer, Local_Warning_Restores, Depth);
   end Append_Local_Warning_Restore;

   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Suppressions
        (Buffer, Initialization_Warning_Suppressions, Depth);
   end Append_Initialization_Warning_Suppression;

   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Restores
        (Buffer, Initialization_Warning_Restores, Depth);
   end Append_Initialization_Warning_Restore;

   procedure Append_Channel_Staged_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Suppressions
        (Buffer, Channel_Staged_Call_Warning_Suppressions, Depth);
   end Append_Channel_Staged_Call_Warning_Suppression;

   procedure Append_Channel_Staged_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Restores
        (Buffer, Channel_Staged_Call_Warning_Restores, Depth);
   end Append_Channel_Staged_Call_Warning_Restore;

   procedure Append_Task_Assignment_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Suppressions
        (Buffer, Task_Assignment_Warning_Suppressions, Depth);
   end Append_Task_Assignment_Warning_Suppression;

   procedure Append_Task_Assignment_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Restores
        (Buffer, Task_Assignment_Warning_Restores, Depth);
   end Append_Task_Assignment_Warning_Restore;

   procedure Append_Task_If_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Suppressions
        (Buffer, Task_If_Warning_Suppressions, Depth);
   end Append_Task_If_Warning_Suppression;

   procedure Append_Task_If_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Restores
        (Buffer, Task_If_Warning_Restores, Depth);
   end Append_Task_If_Warning_Restore;

   procedure Append_Task_Channel_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Suppressions
        (Buffer, Task_Channel_Call_Warning_Suppressions, Depth);
   end Append_Task_Channel_Call_Warning_Suppression;

   procedure Append_Task_Channel_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) is
   begin
      Append_Gnatprove_Warning_Restores
        (Buffer, Task_Channel_Call_Warning_Restores, Depth);
   end Append_Task_Channel_Call_Warning_Restore;

   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural) is
      Free_Call : constant String :=
        (if Item.Is_Constant and then not Has_Text (Item.Free_Proc)
         then "Dispose_" & Sanitized_Helper_Name (FT.To_String (Item.Type_Name))
         elsif Has_Text (Item.Free_Proc)
         then FT.To_String (Item.Free_Proc)
         else "Free_" & Sanitized_Helper_Name (FT.To_String (Item.Type_Name)));
   begin
      case Item.Action is
         when Cleanup_Deallocate =>
            if Item.Is_Constant then
               if not Item.Always_Terminates_Suppression_OK then
                  Raise_Internal
                    ("constant cleanup warning suppression requires a shared runtime Free"
                     & " with Always_Terminates for type "
                     & FT.To_String (Item.Type_Name)
                     & " (" & Free_Call & ")");
               end if;
               Append_Gnatprove_Warning_Suppression
                 (Buffer,
                  "implicit aspect Always_Terminates",
                  "shared runtime cleanup termination is accepted",
                  Depth);
               Append_Local_Warning_Suppression (Buffer, Depth);
               Append_Line (Buffer, "declare", Depth);
               Append_Line
                 (Buffer,
                  "Cleanup_Target : "
                  & FT.To_String (Item.Type_Name)
                  & " := "
                  & FT.To_String (Item.Name)
                  & ";",
                  Depth + 1);
               Append_Line (Buffer, "begin", Depth);
               Append_Line
                 (Buffer,
                  Free_Call & " (Cleanup_Target);",
                  Depth + 1);
               Append_Line (Buffer, "end;", Depth);
               Append_Local_Warning_Restore (Buffer, Depth);
               Append_Gnatprove_Warning_Restore
                 (Buffer,
                  "implicit aspect Always_Terminates",
                  Depth);
            else
               Append_Line
                 (Buffer,
                  Free_Call & " (" & FT.To_String (Item.Name) & ");",
                  Depth);
               if not Has_Text (Item.Free_Proc) then
                  Append_Line
                    (Buffer,
                     "pragma Assert (" & FT.To_String (Item.Name) & " = null);",
                     Depth);
               end if;
            end if;
         when Cleanup_Reset_Null =>
            Append_Line
              (Buffer,
               FT.To_String (Item.Name) & " := null;",
               Depth);
      end case;
   end Render_Cleanup_Item;

   procedure Render_Active_Cleanup
     (Buffer    : in out SU.Unbounded_String;
      State     : Emit_State;
      Depth     : Natural;
      Skip_Name : String := "") is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return;
      end if;
      for Frame_Index in reverse State.Cleanup_Stack.First_Index .. State.Cleanup_Stack.Last_Index loop
         declare
            Frame : constant Cleanup_Frame := State.Cleanup_Stack (Frame_Index);
         begin
            for Item_Index in reverse Frame.Items.First_Index .. Frame.Items.Last_Index loop
               if Skip_Name'Length = 0
                 or else FT.To_String (Frame.Items (Item_Index).Name) /= Skip_Name
               then
                  Render_Cleanup_Item (Buffer, Frame.Items (Item_Index), Depth);
               end if;
            end loop;
         end;
      end loop;
   end Render_Active_Cleanup;

   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural) is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return;
      end if;

      declare
         Frame : constant Cleanup_Frame := State.Cleanup_Stack.Last_Element;
      begin
         for Item_Index in reverse Frame.Items.First_Index .. Frame.Items.Last_Index loop
            Render_Cleanup_Item (Buffer, Frame.Items (Item_Index), Depth);
         end loop;
      end;
   end Render_Current_Cleanup_Frame;

   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean is
   begin
      if State.Cleanup_Stack.Is_Empty then
         return False;
      end if;

      for Frame of State.Cleanup_Stack loop
         if not Frame.Items.Is_Empty then
            return True;
         end if;
      end loop;
      return False;
   end Has_Active_Cleanup_Items;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural) is
   begin
      if Declarations.Is_Empty then
         return;
      end if;
      for Reverse_Index in reverse Declarations.First_Index .. Declarations.Last_Index loop
         declare
            Decl : constant CM.Resolved_Object_Decl := Declarations (Reverse_Index);
         begin
            if Is_Owner_Access (Decl.Type_Info) then
               for Name of Decl.Names loop
                  Render_Cleanup_Item
                    (Buffer,
                     (Action    => Cleanup_Deallocate,
                      Name      => Name,
                      Type_Name => Decl.Type_Info.Name,
                      Free_Proc => FT.To_UString (""),
                      Is_Constant => False,
                      Always_Terminates_Suppression_OK => False),
                     Depth);
               end loop;
            end if;
         end;
      end loop;
   end Render_Cleanup;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural) is
   begin
      if Declarations.Is_Empty then
         return;
      end if;
      for Reverse_Index in reverse Declarations.First_Index .. Declarations.Last_Index loop
         declare
            Decl : constant CM.Object_Decl := Declarations (Reverse_Index);
         begin
            if Is_Owner_Access (Decl.Type_Info) then
               for Name of Decl.Names loop
                  Render_Cleanup_Item
                    (Buffer,
                     (Action    => Cleanup_Deallocate,
                      Name      => Name,
                      Type_Name => Decl.Type_Info.Name,
                      Free_Proc => FT.To_UString (""),
                      Is_Constant => False,
                      Always_Terminates_Suppression_OK => False),
                     Depth);
               end loop;
            end if;
         end;
      end loop;
   end Render_Cleanup;

   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean is
   begin
      if Item = null then
         return False;
      end if;

      case Item.Kind is
         when CM.Stmt_Exit =>
            return True;
         when CM.Stmt_If =>
            if Statements_Contain_Exit (Item.Then_Stmts) then
               return True;
            end if;
            for Part of Item.Elsifs loop
               if Statements_Contain_Exit (Part.Statements) then
                  return True;
               end if;
            end loop;
            return Item.Has_Else and then Statements_Contain_Exit (Item.Else_Stmts);
         when CM.Stmt_Case =>
            for Arm of Item.Case_Arms loop
               if Statements_Contain_Exit (Arm.Statements) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Stmt_Loop | CM.Stmt_While | CM.Stmt_For =>
            return Statements_Contain_Exit (Item.Body_Stmts);
         when CM.Stmt_Match =>
            for Arm of Item.Match_Arms loop
               if Statements_Contain_Exit (Arm.Statements) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Stmt_Select =>
            for Arm of Item.Arms loop
               case Arm.Kind is
                  when CM.Select_Arm_Channel =>
                     if Statements_Contain_Exit (Arm.Channel_Data.Statements) then
                        return True;
                     end if;
                  when CM.Select_Arm_Delay =>
                     if Statements_Contain_Exit (Arm.Delay_Data.Statements) then
                        return True;
                     end if;
                  when CM.Select_Arm_Unknown =>
                     return True;
               end case;
            end loop;
            return False;
         when CM.Stmt_Unknown =>
            return True;
         when CM.Stmt_Object_Decl
            | CM.Stmt_Destructure_Decl
            | CM.Stmt_Assign
            | CM.Stmt_Call
            | CM.Stmt_Return
            | CM.Stmt_Send
            | CM.Stmt_Receive
            | CM.Stmt_Try_Send
            | CM.Stmt_Try_Receive
            | CM.Stmt_Delay =>
            return False;
      end case;
   end Statement_Contains_Exit;

   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean is
   begin
      for Item of Statements loop
         if Statement_Contains_Exit (Item) then
            return True;
         end if;
      end loop;
      return False;
   end Statements_Contain_Exit;

   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean is
   begin
      if Item = null then
         return True;
      end if;

      case Item.Kind is
         when CM.Stmt_Return =>
            return False;
         when CM.Stmt_If =>
            if Statements_Fall_Through (Item.Then_Stmts) then
               return True;
            end if;
            for Part of Item.Elsifs loop
               if Statements_Fall_Through (Part.Statements) then
                  return True;
               end if;
            end loop;
            if not Item.Has_Else then
               return True;
            end if;
            return Statements_Fall_Through (Item.Else_Stmts);
         when CM.Stmt_Case =>
            for Arm of Item.Case_Arms loop
               if Statements_Fall_Through (Arm.Statements) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Stmt_Loop =>
            return Statements_Contain_Exit (Item.Body_Stmts);
         when CM.Stmt_Match =>
            for Arm of Item.Match_Arms loop
               if Statements_Fall_Through (Arm.Statements) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Stmt_Select =>
            for Arm of Item.Arms loop
               case Arm.Kind is
                  when CM.Select_Arm_Channel =>
                     if Statements_Fall_Through (Arm.Channel_Data.Statements) then
                        return True;
                     end if;
                  when CM.Select_Arm_Delay =>
                     if Statements_Fall_Through (Arm.Delay_Data.Statements) then
                        return True;
                     end if;
                  when CM.Select_Arm_Unknown =>
                     return True;
               end case;
            end loop;
            return False;
         when CM.Stmt_Unknown
            | CM.Stmt_Object_Decl
            | CM.Stmt_Destructure_Decl
            | CM.Stmt_Assign
            | CM.Stmt_Call
            | CM.Stmt_While
            | CM.Stmt_For
            | CM.Stmt_Exit
            | CM.Stmt_Send
            | CM.Stmt_Receive
            | CM.Stmt_Try_Send
            | CM.Stmt_Try_Receive
            | CM.Stmt_Delay =>
            return True;
      end case;
   end Statement_Falls_Through;

   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean is
   begin
      if Statements.Is_Empty then
         return True;
      end if;

      for Item of Statements loop
         if not Statement_Falls_Through (Item) then
            return False;
         end if;
      end loop;
      return True;
   end Statements_Fall_Through;

   procedure Add_Body_With
     (Context : in out Emit_Context;
      Name    : String) is
   begin
      for Item of Context.Body_Withs loop
         if FT.To_String (Item) = Name then
            return;
         end if;
      end loop;
      Context.Body_Withs.Append (FT.To_UString (Name));
   end Add_Body_With;

   procedure Add_Imported_Use_Type
     (Context : in out Emit_Context;
      Name    : String) is
   begin
      for Item of Context.Imported_Use_Types loop
         if FT.To_String (Item) = Name then
            return;
         end if;
      end loop;
      Context.Imported_Use_Types.Append (FT.To_UString (Name));
   end Add_Imported_Use_Type;

   function Package_Select_Refined_State
     (Context : Emit_Context) return String is
      Constituents : FT.UString_Vectors.Vector;
   begin
      for Name of Context.Package_Dispatcher_Names loop
         Constituents.Append (Name);
      end loop;
      for Name of Context.Package_Dispatcher_Timer_Names loop
         Constituents.Append (Name);
      end loop;
      for Name of Context.Package_Select_Rotation_Names loop
         Constituents.Append (Name);
      end loop;
      return Join_Names (Constituents);
   end Package_Select_Refined_State;
end Safe_Frontend.Ada_Emit.Internal;
