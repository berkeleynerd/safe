with Ada.Containers;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;

package body Safe_Frontend.Mir_Bronze is
   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   package Span_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => FT.Source_Span,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => FT."=");

   package Local_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => GM.Local_Entry,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => GM."=");

   package Set_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String_Sets.Set,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => String_Sets."=");

   package Name_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Marker_Binding is record
      Markers   : String_Sets.Set;
      Use_Spans : Span_Maps.Map;
   end record;

   package Marker_Binding_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Marker_Binding);

   type Call_Site is record
      Callee         : FT.UString := FT.To_UString ("");
      Span           : FT.Source_Span := FT.Null_Span;
      Input_Bindings : Marker_Binding_Vectors.Vector;
      Output_Bindings : Marker_Binding_Vectors.Vector;
   end record;

   package Call_Site_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Call_Site);

   type Callable_Signature is record
      Param_Names : FT.UString_Vectors.Vector;
      Param_Modes : FT.UString_Vectors.Vector;
   end record;

   package Signature_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Callable_Signature,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Direct_Summary is record
      Name           : FT.UString := FT.To_UString ("");
      Kind           : FT.UString := FT.To_UString ("");
      Is_Task        : Boolean := False;
      Priority       : Long_Long_Integer := 0;
      Direct_Reads   : String_Sets.Set;
      Direct_Writes  : String_Sets.Set;
      Direct_Shared_Reads  : String_Sets.Set;
      Direct_Shared_Writes : String_Sets.Set;
      Direct_Channels : String_Sets.Set;
      Direct_Sends  : String_Sets.Set;
      Direct_Receives : String_Sets.Set;
      Direct_Legacy_Channels : String_Sets.Set;
      Direct_Calls   : String_Sets.Set;
      Direct_Inputs  : String_Sets.Set;
      Direct_Outputs : String_Sets.Set;
      Reads          : String_Sets.Set;
      Writes         : String_Sets.Set;
      Shared_Reads   : String_Sets.Set;
      Shared_Writes  : String_Sets.Set;
      Channels       : String_Sets.Set;
      Sends          : String_Sets.Set;
      Receives       : String_Sets.Set;
      Legacy_Channels : String_Sets.Set;
      Calls          : String_Sets.Set;
      Inputs         : String_Sets.Set;
      Outputs        : String_Sets.Set;
      Span           : FT.Source_Span := FT.Null_Span;
      Use_Spans      : Span_Maps.Map;
      Call_Sites     : Call_Site_Vectors.Vector;
   end record;

   package Integer_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Long_Long_Integer,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Summary_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Direct_Summary,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   use type Ada.Containers.Count_Type;
   use type FT.Source_Span;
   use type GM.Expr_Access;
   use type GM.Expr_Kind;
   use type GM.Select_Arm_Kind;
   use type String_Sets.Set;

   Bronze_Internal : exception;

   function UString_Value (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end UString_Value;

   procedure Raise_Internal (Message : String);
   pragma No_Return (Raise_Internal);

   function Lower (Value : String) return String renames FT.Lowercase;
   function Canonical_Name (Value : String) return String;
   function Tail_Name (Value : String) return String;
   function Sanitize_Type_Name_Component (Value : String) return String;
   function Shared_Wrapper_Object_Name (Root_Name : String) return String;
   function Shared_Public_Helper_Base_Name (Root_Name : String) return String;
   function Starts_With (Text : String; Prefix : String) return Boolean;
   function Ends_With (Text : String; Suffix : String) return Boolean;
   function Is_Synthetic_Attribute_Marker
     (Name         : String;
      Global_Spans : Span_Maps.Map) return Boolean;

   function Flatten_Name (Expr : GM.Expr_Access) return String;
   function Root_Name (Expr : GM.Expr_Access) return String;
   function Signature_For (Graph : GM.Graph_Entry) return Callable_Signature;
   function Signature_For (Value : GM.External_Entry) return Callable_Signature;
   function Has_Span (Span : FT.Source_Span) return Boolean;
   function Earlier_Span
     (Left  : FT.Source_Span;
     Right : FT.Source_Span) return FT.Source_Span;
   procedure Note_Use_Span
     (Name      : String;
      Span      : FT.Source_Span;
      Use_Spans : in out Span_Maps.Map);
   procedure Note_Binding_Marker
     (Marker  : String;
      Span    : FT.Source_Span;
      Binding : in out Marker_Binding);
   function Join_Strings
     (Items     : FT.UString_Vectors.Vector;
      Separator : String := ", ") return String;
   procedure Sort_Strings (Items : in out FT.UString_Vectors.Vector);
   procedure Sort_Graph_Summaries (Items : in out Graph_Summary_Vectors.Vector);
   procedure Sort_Ownership (Items : in out Ownership_Vectors.Vector);
   procedure Sort_Ceilings (Items : in out Ceiling_Vectors.Vector);
   procedure Sort_Shared_Ceilings (Items : in out Shared_Ceiling_Vectors.Vector);
   function To_Vector (Items : String_Sets.Set) return FT.UString_Vectors.Vector;
   function To_Set (Items : FT.UString_Vectors.Vector) return String_Sets.Set;
   function Local_Metadata (Graph : GM.Graph_Entry) return Local_Maps.Map;
   procedure Note_Read
     (Name      : String;
     Locals    : Local_Maps.Map;
     Reads     : in out String_Sets.Set;
     Inputs    : in out String_Sets.Set;
     Use_Spans : in out Span_Maps.Map;
      Span      : FT.Source_Span;
      Binding   : access Marker_Binding := null);
   procedure Note_Write
     (Name      : String;
      Locals    : Local_Maps.Map;
      Writes    : in out String_Sets.Set;
      Outputs   : in out String_Sets.Set;
      Use_Spans : in out Span_Maps.Map;
      Span      : FT.Source_Span;
      Binding   : access Marker_Binding := null);
   procedure Note_Shared_Read
     (Name         : String;
      Shared_Reads : in out String_Sets.Set;
      Inputs       : in out String_Sets.Set;
      Use_Spans    : in out Span_Maps.Map;
      Span         : FT.Source_Span);
   procedure Note_Shared_Write
     (Name          : String;
      Shared_Writes : in out String_Sets.Set;
      Outputs       : in out String_Sets.Set;
      Use_Spans     : in out Span_Maps.Map;
      Span          : FT.Source_Span);
   function Try_Shared_Call
     (Call_Name              : String;
      Shared_Wrappers        : Name_Maps.Map;
      Shared_Helper_Prefixes : Name_Maps.Map;
      Root_Name              : out FT.UString;
      Operation              : out FT.UString) return Boolean;
   procedure Mark_Shared_Call
     (Root_Name     : String;
      Operation     : String;
      Shared_Reads  : in out String_Sets.Set;
      Shared_Writes : in out String_Sets.Set;
      Inputs        : in out String_Sets.Set;
      Outputs       : in out String_Sets.Set;
      Use_Spans     : in out Span_Maps.Map;
      Span          : FT.Source_Span);
   procedure Collect_Output_Binding
     (Expr    : GM.Expr_Access;
      Locals  : Local_Maps.Map;
      Binding : in out Marker_Binding);
   procedure Walk_Expr
     (Expr        : GM.Expr_Access;
      Locals      : Local_Maps.Map;
      Callable_Names : String_Sets.Set;
      Signatures  : Signature_Maps.Map;
      Shared_Wrappers : Name_Maps.Map;
      Shared_Helper_Prefixes : Name_Maps.Map;
      Reads       : in out String_Sets.Set;
      Shared_Reads : in out String_Sets.Set;
      Shared_Writes : in out String_Sets.Set;
      Calls       : in out String_Sets.Set;
      Inputs      : in out String_Sets.Set;
      Outputs     : in out String_Sets.Set;
      Use_Spans   : in out Span_Maps.Map;
      Call_Sites  : in out Call_Site_Vectors.Vector;
      Binding     : access Marker_Binding := null);
   function External_Summary
     (Value               : GM.External_Entry;
      Shared_Object_Names : String_Sets.Set) return Direct_Summary;
   function Formal_Index
     (Signature   : Callable_Signature;
      Formal_Name : String) return Natural;
   procedure Project_Call_Markers
     (Markers       : String_Sets.Set;
      Signature     : Callable_Signature;
      Bindings      : Marker_Binding_Vectors.Vector;
      Call_Span     : FT.Source_Span;
      Target        : in out String_Sets.Set;
      Target_Spans  : in out Span_Maps.Map;
      Ignore_Return : Boolean := False);
   function Earliest_Task_Use_Span
     (Task_Names : FT.UString_Vectors.Vector;
      Summaries  : Summary_Maps.Map;
      Name       : String) return FT.Source_Span;
   function Local_Use_Note (Span : FT.Source_Span) return String;
   function Dependency_Vector
     (Outputs : String_Sets.Set;
      Inputs  : String_Sets.Set) return Depends_Vectors.Vector;
   function Find_Task_Index
     (Tasks : CM.Resolved_Task_Vectors.Vector;
      Name  : String) return Natural;
   function Use_Span_For
     (Summary      : Direct_Summary;
      Channel_Name : String) return FT.Source_Span;
   function Contract_Note
     (Direction : String;
      Allowed   : String_Sets.Set) return String;

   procedure Raise_Internal (Message : String) is
   begin
      raise Bronze_Internal with Message;
   end Raise_Internal;

   function Canonical_Name (Value : String) return String is
   begin
      return FT.Lowercase (Value);
   end Canonical_Name;

   function Tail_Name (Value : String) return String is
      Dot : constant Natural :=
        Ada.Strings.Fixed.Index (Value, ".", Ada.Strings.Backward);
   begin
      if Dot = 0 or else Dot = Value'Last then
         return Value;
      end if;
      return Value (Dot + 1 .. Value'Last);
   end Tail_Name;

   function Sanitize_Type_Name_Component (Value : String) return String is
      Result : FT.UString := FT.To_UString ("");
      Last_Was_Underscore : Boolean := False;
   begin
      for Ch of Value loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := FT.US."&" (Result, FT.To_UString ((1 => Ch)));
            Last_Was_Underscore := False;
         elsif not Last_Was_Underscore then
            Result := FT.US."&" (Result, FT.To_UString ("_"));
            Last_Was_Underscore := True;
         end if;
      end loop;

      declare
         Text  : constant String := FT.To_String (Result);
         First : Positive := Text'First;
         Last  : Natural := Text'Last;
      begin
         while First <= Text'Last and then Text (First) = '_' loop
            First := First + 1;
         end loop;
         while Last >= First and then Text (Last) = '_' loop
            Last := Last - 1;
         end loop;
         if Last < First then
            return "value";
         end if;
         return Text (First .. Last);
      end;
   end Sanitize_Type_Name_Component;

   function Shared_Wrapper_Object_Name (Root_Name : String) return String is
   begin
      return
        "Safe_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Wrapper_Object_Name;

   function Shared_Public_Helper_Base_Name (Root_Name : String) return String is
   begin
      return
        "Safe_Public_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Public_Helper_Base_Name;

   function Starts_With (Text : String; Prefix : String) return Boolean is
   begin
      if Prefix'Length = 0 then
         return True;
      elsif Text'Length < Prefix'Length then
         return False;
      end if;

      return Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Ends_With (Text : String; Suffix : String) return Boolean is
   begin
      if Suffix'Length = 0 then
         return True;
      elsif Text'Length < Suffix'Length then
         return False;
      end if;

      return Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix;
   end Ends_With;

   function Is_Synthetic_Attribute_Marker
     (Name         : String;
      Global_Spans : Span_Maps.Map) return Boolean
   is
      First_Dot : constant Natural := Ada.Strings.Fixed.Index (Name, ".");
      Last_Dot  : constant Natural :=
        Ada.Strings.Fixed.Index (Name, ".", Ada.Strings.Backward);
      Root_Name : constant String :=
        (if First_Dot > 1 then Name (Name'First .. First_Dot - 1) else "");
      Is_Attribute_Name : constant Boolean :=
        Ends_With (Name, ".first")
        or else Ends_With (Name, ".last")
        or else Ends_With (Name, ".length");
   begin
      return Is_Attribute_Name
        and then First_Dot = Last_Dot
        and then Root_Name /= ""
        and then not Global_Spans.Contains (Root_Name);
   end Is_Synthetic_Attribute_Marker;

   function Signature_For (Graph : GM.Graph_Entry) return Callable_Signature is
      Result : Callable_Signature;
   begin
      for Local of Graph.Locals loop
         if UString_Value (Local.Kind) = "param" then
            Result.Param_Names.Append (Local.Name);
            Result.Param_Modes.Append (Local.Mode);
         end if;
      end loop;
      return Result;
   end Signature_For;

   function Signature_For (Value : GM.External_Entry) return Callable_Signature is
      Result : Callable_Signature;
   begin
      for Param of Value.Params loop
         Result.Param_Names.Append (Param.Name);
         Result.Param_Modes.Append (Param.Mode);
      end loop;
      return Result;
   end Signature_For;

   function Flatten_Name (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = GM.Expr_Select then
         declare
            Prefix : constant String := Flatten_Name (Expr.Prefix);
         begin
            if Prefix = "" then
               return UString_Value (Expr.Selector);
            end if;
            return Prefix & "." & UString_Value (Expr.Selector);
         end;
      end if;
      return "";
   end Flatten_Name;

   function Root_Name (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = GM.Expr_Select then
         return Root_Name (Expr.Prefix);
      elsif Expr.Kind = GM.Expr_Conversion then
         return Root_Name (Expr.Inner);
      end if;
      return "";
   end Root_Name;

   function Has_Span (Span : FT.Source_Span) return Boolean is
   begin
      return Span /= FT.Null_Span;
   end Has_Span;

   function Earlier_Span
     (Left  : FT.Source_Span;
      Right : FT.Source_Span) return FT.Source_Span
   is
   begin
      if not Has_Span (Left) then
         return Right;
      elsif not Has_Span (Right) then
         return Left;
      elsif Right.Start_Pos.Line < Left.Start_Pos.Line then
         return Right;
      elsif Right.Start_Pos.Line = Left.Start_Pos.Line
        and then Right.Start_Pos.Column < Left.Start_Pos.Column
      then
         return Right;
      end if;
      return Left;
   end Earlier_Span;

   procedure Note_Use_Span
     (Name      : String;
      Span      : FT.Source_Span;
      Use_Spans : in out Span_Maps.Map)
   is
   begin
      if Name = "" or else not Has_Span (Span) then
         return;
      elsif Use_Spans.Contains (Name) then
         Use_Spans.Replace (Name, Earlier_Span (Use_Spans.Element (Name), Span));
      else
         Use_Spans.Include (Name, Span);
      end if;
   end Note_Use_Span;

   procedure Note_Binding_Marker
     (Marker  : String;
      Span    : FT.Source_Span;
      Binding : in out Marker_Binding)
   is
   begin
      if Marker = "" then
         return;
      end if;

      Binding.Markers.Include (Marker);
      Note_Use_Span (Marker, Span, Binding.Use_Spans);
   end Note_Binding_Marker;

   function Join_Strings
     (Items     : FT.UString_Vectors.Vector;
      Separator : String := ", ") return String
   is
      Result : FT.UString := FT.To_UString ("");
   begin
      if Items.Is_Empty then
         return "";
      end if;

      for Index in Items.First_Index .. Items.Last_Index loop
         if Index > Items.First_Index then
            Result := FT.US."&" (Result, FT.To_UString (Separator));
         end if;
         Result := FT.US."&" (Result, Items (Index));
      end loop;

      return UString_Value (Result);
   end Join_Strings;

   procedure Sort_Strings (Items : in out FT.UString_Vectors.Vector) is
   begin
      if Items.Length <= 1 then
         return;
      end if;
      for I in Items.First_Index .. Items.Last_Index loop
         for J in I + 1 .. Items.Last_Index loop
            if Lower (UString_Value (Items (J))) < Lower (UString_Value (Items (I))) then
               declare
                  Temp : constant FT.UString := Items (I);
               begin
                  Items.Replace_Element (I, Items (J));
                  Items.Replace_Element (J, Temp);
               end;
            end if;
         end loop;
      end loop;
   end Sort_Strings;

   procedure Sort_Graph_Summaries (Items : in out Graph_Summary_Vectors.Vector) is
   begin
      if Items.Length <= 1 then
         return;
      end if;

      for I in Items.First_Index .. Items.Last_Index loop
         for J in I + 1 .. Items.Last_Index loop
            if Lower (UString_Value (Items (J).Name)) < Lower (UString_Value (Items (I).Name)) then
               declare
                  Temp : constant Graph_Summary := Items (I);
               begin
                  Items.Replace_Element (I, Items (J));
                  Items.Replace_Element (J, Temp);
               end;
            end if;
         end loop;
      end loop;
   end Sort_Graph_Summaries;

   procedure Sort_Ownership (Items : in out Ownership_Vectors.Vector) is
   begin
      if Items.Length <= 1 then
         return;
      end if;

      for I in Items.First_Index .. Items.Last_Index loop
         for J in I + 1 .. Items.Last_Index loop
            if Lower (UString_Value (Items (J).Global_Name)) < Lower (UString_Value (Items (I).Global_Name))
              or else
                (Lower (UString_Value (Items (J).Global_Name)) = Lower (UString_Value (Items (I).Global_Name))
                 and then Lower (UString_Value (Items (J).Task_Name)) < Lower (UString_Value (Items (I).Task_Name)))
            then
               declare
                  Temp : constant Ownership_Entry := Items (I);
               begin
                  Items.Replace_Element (I, Items (J));
                  Items.Replace_Element (J, Temp);
               end;
            end if;
         end loop;
      end loop;
   end Sort_Ownership;

   procedure Sort_Ceilings (Items : in out Ceiling_Vectors.Vector) is
   begin
      if Items.Length <= 1 then
         return;
      end if;

      for I in Items.First_Index .. Items.Last_Index loop
         for J in I + 1 .. Items.Last_Index loop
            if Lower (UString_Value (Items (J).Channel_Name)) < Lower (UString_Value (Items (I).Channel_Name)) then
               declare
                  Temp : constant Ceiling_Entry := Items (I);
               begin
                  Items.Replace_Element (I, Items (J));
                  Items.Replace_Element (J, Temp);
               end;
            end if;
         end loop;
      end loop;
   end Sort_Ceilings;

   procedure Sort_Shared_Ceilings
     (Items : in out Shared_Ceiling_Vectors.Vector)
   is
   begin
      if Items.Length <= 1 then
         return;
      end if;

      for I in Items.First_Index .. Items.Last_Index loop
         for J in I + 1 .. Items.Last_Index loop
            if Lower (UString_Value (Items (J).Shared_Name))
              < Lower (UString_Value (Items (I).Shared_Name))
            then
               declare
                  Temp : constant Shared_Ceiling_Entry := Items (I);
               begin
                  Items.Replace_Element (I, Items (J));
                  Items.Replace_Element (J, Temp);
               end;
            end if;
         end loop;
      end loop;
   end Sort_Shared_Ceilings;

   function To_Vector (Items : String_Sets.Set) return FT.UString_Vectors.Vector is
      Result : FT.UString_Vectors.Vector;
      Cursor : String_Sets.Cursor := Items.First;
   begin
      while String_Sets.Has_Element (Cursor) loop
         Result.Append (FT.To_UString (String_Sets.Element (Cursor)));
         String_Sets.Next (Cursor);
      end loop;
      Sort_Strings (Result);
      return Result;
   end To_Vector;

   function To_Set (Items : FT.UString_Vectors.Vector) return String_Sets.Set is
      Result : String_Sets.Set;
   begin
      if not Items.Is_Empty then
         for Item of Items loop
            Result.Include (UString_Value (Item));
         end loop;
      end if;
      return Result;
   end To_Set;

   function Local_Metadata (Graph : GM.Graph_Entry) return Local_Maps.Map is
      Result : Local_Maps.Map;
   begin
      for Local of Graph.Locals loop
         Result.Include (UString_Value (Local.Name), Local);
      end loop;
      return Result;
   end Local_Metadata;

   procedure Note_Read
     (Name      : String;
      Locals    : Local_Maps.Map;
      Reads     : in out String_Sets.Set;
      Inputs    : in out String_Sets.Set;
      Use_Spans : in out Span_Maps.Map;
      Span      : FT.Source_Span;
      Binding   : access Marker_Binding := null)
   is
      Local : GM.Local_Entry;
   begin
      if Name = "" then
         return;
      elsif Locals.Contains (Name) then
         Local := Locals.Element (Name);
         if UString_Value (Local.Kind) = "global" then
            Reads.Include (Name);
            Inputs.Include ("global:" & Name);
            Note_Use_Span (Name, Span, Use_Spans);
            if Binding /= null then
               Note_Binding_Marker ("global:" & Name, Span, Binding.all);
            end if;
         elsif UString_Value (Local.Kind) = "param" then
            Inputs.Include ("param:" & Name);
            if Binding /= null then
               Note_Binding_Marker ("param:" & Name, Span, Binding.all);
            end if;
         end if;
      elsif Ada.Strings.Fixed.Index (Name, ".") > 0 then
         Reads.Include (Name);
         Inputs.Include ("global:" & Name);
         Note_Use_Span (Name, Span, Use_Spans);
         if Binding /= null then
            Note_Binding_Marker ("global:" & Name, Span, Binding.all);
         end if;
      end if;
   end Note_Read;

   procedure Note_Write
     (Name      : String;
      Locals    : Local_Maps.Map;
      Writes    : in out String_Sets.Set;
      Outputs   : in out String_Sets.Set;
      Use_Spans : in out Span_Maps.Map;
      Span      : FT.Source_Span;
      Binding   : access Marker_Binding := null)
   is
      Local : GM.Local_Entry;
   begin
      if Name = "" then
         return;
      elsif Locals.Contains (Name) then
         Local := Locals.Element (Name);
         if UString_Value (Local.Kind) = "global" then
            Writes.Include (Name);
            Outputs.Include ("global:" & Name);
            Note_Use_Span (Name, Span, Use_Spans);
            if Binding /= null then
               Note_Binding_Marker ("global:" & Name, Span, Binding.all);
            end if;
         elsif UString_Value (Local.Kind) = "param"
           and then UString_Value (Local.Mode) in "mut" | "out" | "in out"
         then
            Outputs.Include ("param:" & Name);
            if Binding /= null then
               Note_Binding_Marker ("param:" & Name, Span, Binding.all);
            end if;
         end if;
      elsif Ada.Strings.Fixed.Index (Name, ".") > 0 then
         Writes.Include (Name);
         Outputs.Include ("global:" & Name);
         Note_Use_Span (Name, Span, Use_Spans);
         if Binding /= null then
            Note_Binding_Marker ("global:" & Name, Span, Binding.all);
         end if;
      end if;
   end Note_Write;

   procedure Note_Shared_Read
     (Name         : String;
      Shared_Reads : in out String_Sets.Set;
      Inputs       : in out String_Sets.Set;
      Use_Spans    : in out Span_Maps.Map;
      Span         : FT.Source_Span)
   is
   begin
      if Name = "" then
         return;
      end if;

      Shared_Reads.Include (Name);
      Inputs.Include ("global:" & Name);
      Note_Use_Span (Name, Span, Use_Spans);
   end Note_Shared_Read;

   procedure Note_Shared_Write
     (Name          : String;
      Shared_Writes : in out String_Sets.Set;
      Outputs       : in out String_Sets.Set;
      Use_Spans     : in out Span_Maps.Map;
      Span          : FT.Source_Span)
   is
   begin
      if Name = "" then
         return;
      end if;

      Shared_Writes.Include (Name);
      Outputs.Include ("global:" & Name);
      Note_Use_Span (Name, Span, Use_Spans);
   end Note_Shared_Write;

   function Try_Shared_Call
     (Call_Name              : String;
      Shared_Wrappers        : Name_Maps.Map;
      Shared_Helper_Prefixes : Name_Maps.Map;
      Root_Name              : out FT.UString;
      Operation              : out FT.UString) return Boolean
   is
      Canonical_Call : constant String := Canonical_Name (Call_Name);
      Dot            : constant Natural :=
        Ada.Strings.Fixed.Index (Canonical_Call, ".", Ada.Strings.Backward);
      Cursor         : Name_Maps.Cursor;
      Best_Length    : Natural := 0;
      Best_Root      : FT.UString := FT.To_UString ("");
   begin
      Root_Name := FT.To_UString ("");
      Operation := FT.To_UString ("");

      if Dot > 1 and then Dot < Canonical_Call'Last then
         declare
            Wrapper : constant String :=
              Canonical_Call (Canonical_Call'First .. Dot - 1);
         begin
            if Shared_Wrappers.Contains (Wrapper) then
               Root_Name := FT.To_UString (Shared_Wrappers.Element (Wrapper));
               Operation := FT.To_UString (Canonical_Call (Dot + 1 .. Canonical_Call'Last));
               return True;
            end if;
         end;
      end if;

      Cursor := Shared_Helper_Prefixes.First;
      while Name_Maps.Has_Element (Cursor) loop
         declare
            Prefix : constant String := Name_Maps.Key (Cursor);
         begin
            if Starts_With (Canonical_Call, Prefix)
              and then Canonical_Call'Length > Prefix'Length
              and then Prefix'Length > Best_Length
            then
               Best_Length := Prefix'Length;
               Best_Root := FT.To_UString (Name_Maps.Element (Cursor));
            end if;
            Name_Maps.Next (Cursor);
         end;
      end loop;

      if Best_Length > 0 then
         Root_Name := Best_Root;
         Operation :=
           FT.To_UString (Canonical_Call (Best_Length + 1 .. Canonical_Call'Last));
         return True;
      end if;

      return False;
   end Try_Shared_Call;

   procedure Mark_Shared_Call
     (Root_Name     : String;
      Operation     : String;
      Shared_Reads  : in out String_Sets.Set;
      Shared_Writes : in out String_Sets.Set;
      Inputs        : in out String_Sets.Set;
      Outputs       : in out String_Sets.Set;
      Use_Spans     : in out Span_Maps.Map;
      Span          : FT.Source_Span)
   is
      Op : constant String := Lower (Operation);
   begin
      if Root_Name = "" then
         return;
      elsif Op = "pop_last" or else Op = "remove" then
         Note_Shared_Read (Root_Name, Shared_Reads, Inputs, Use_Spans, Span);
         Note_Shared_Write (Root_Name, Shared_Writes, Outputs, Use_Spans, Span);
      elsif Op = "append"
        or else Op = "set"
        or else Op = "initialize"
        or else Starts_With (Op, "set_")
      then
         Note_Shared_Write (Root_Name, Shared_Writes, Outputs, Use_Spans, Span);
      elsif Op = "contains"
        or else Op = "get"
        or else Starts_With (Op, "get_")
      then
         Note_Shared_Read (Root_Name, Shared_Reads, Inputs, Use_Spans, Span);
      end if;
   end Mark_Shared_Call;

   procedure Collect_Output_Binding
     (Expr    : GM.Expr_Access;
      Locals  : Local_Maps.Map;
      Binding : in out Marker_Binding)
   is
      Root          : constant String := Root_Name (Expr);
      Full          : constant String := Flatten_Name (Expr);
      Local         : GM.Local_Entry;

      procedure Add_Name (Name : String) is
      begin
         if Name = "" then
            return;
         elsif Locals.Contains (Name) then
            Local := Locals.Element (Name);
            if UString_Value (Local.Kind) = "global" then
               Note_Binding_Marker ("global:" & Name, Expr.Span, Binding);
            elsif UString_Value (Local.Kind) = "param"
              and then UString_Value (Local.Mode) in "mut" | "out" | "in out"
            then
               Note_Binding_Marker ("param:" & Name, Expr.Span, Binding);
            end if;
         elsif Ada.Strings.Fixed.Index (Name, ".") > 0 then
            Note_Binding_Marker ("global:" & Name, Expr.Span, Binding);
         end if;
      end Add_Name;
   begin
      if Expr = null then
         return;
      elsif Root /= "" and then Locals.Contains (Root) then
         Add_Name (Root);
      elsif Full /= "" then
         Add_Name (Full);
      end if;
   end Collect_Output_Binding;

   procedure Walk_Expr
     (Expr        : GM.Expr_Access;
      Locals      : Local_Maps.Map;
      Callable_Names : String_Sets.Set;
      Signatures  : Signature_Maps.Map;
      Shared_Wrappers : Name_Maps.Map;
      Shared_Helper_Prefixes : Name_Maps.Map;
      Reads       : in out String_Sets.Set;
      Shared_Reads : in out String_Sets.Set;
      Shared_Writes : in out String_Sets.Set;
      Calls       : in out String_Sets.Set;
      Inputs      : in out String_Sets.Set;
      Outputs     : in out String_Sets.Set;
      Use_Spans   : in out Span_Maps.Map;
      Call_Sites  : in out Call_Site_Vectors.Vector;
      Binding     : access Marker_Binding := null)
   is
      Root        : FT.UString := FT.To_UString ("");
      Callee      : FT.UString := FT.To_UString ("");
      Full        : FT.UString := FT.To_UString ("");
      Shared_Root : FT.UString := FT.To_UString ("");
      Shared_Op   : FT.UString := FT.To_UString ("");
   begin
      if Expr = null then
         return;
      end if;

      case Expr.Kind is
         when GM.Expr_Ident =>
            Note_Read
              (UString_Value (Expr.Name),
               Locals,
               Reads,
               Inputs,
               Use_Spans,
               Expr.Span,
               Binding);
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "access" then
               Root := FT.To_UString (Root_Name (Expr.Prefix));
               Full := FT.To_UString (Flatten_Name (Expr.Prefix));
               if UString_Value (Root) /= "" and then Locals.Contains (UString_Value (Root)) then
                  Note_Read
                    (UString_Value (Root),
                     Locals,
                     Reads,
                     Inputs,
                     Use_Spans,
                     Expr.Span,
                     Binding);
               else
                  Note_Read
                    (UString_Value (Full),
                     Locals,
                     Reads,
                     Inputs,
                     Use_Spans,
                     Expr.Span,
                     Binding);
               end if;
            elsif Ada.Strings.Fixed.Index (Flatten_Name (Expr), ".") > 0
              and then not Locals.Contains (Root_Name (Expr))
            then
               Note_Read
                 (Flatten_Name (Expr),
                  Locals,
                  Reads,
                  Inputs,
                  Use_Spans,
                  Expr.Span,
                  Binding);
            else
               Walk_Expr
                 (Expr.Prefix,
                  Locals,
                  Callable_Names,
                  Signatures,
                  Shared_Wrappers,
                  Shared_Helper_Prefixes,
                  Reads,
                  Shared_Reads,
                  Shared_Writes,
                  Calls,
                  Inputs,
                  Outputs,
                  Use_Spans,
                  Call_Sites,
                  Binding);
            end if;
         when GM.Expr_Resolved_Index =>
            Walk_Expr
              (Expr.Prefix,
               Locals,
               Callable_Names,
               Signatures,
               Shared_Wrappers,
               Shared_Helper_Prefixes,
               Reads,
               Shared_Reads,
               Shared_Writes,
               Calls,
               Inputs,
               Outputs,
               Use_Spans,
               Call_Sites,
               Binding);
            if not Expr.Args.Is_Empty then
               for Arg of Expr.Args loop
                  Walk_Expr
                    (Arg,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Reads,
                     Shared_Reads,
                     Shared_Writes,
                     Calls,
                     Inputs,
                     Outputs,
                     Use_Spans,
                     Call_Sites,
                     Binding);
               end loop;
            end if;
         when GM.Expr_Conversion | GM.Expr_Unary | GM.Expr_Annotated =>
            Walk_Expr
              (Expr.Inner,
               Locals,
               Callable_Names,
               Signatures,
               Shared_Wrappers,
               Shared_Helper_Prefixes,
               Reads,
               Shared_Reads,
               Shared_Writes,
               Calls,
               Inputs,
               Outputs,
               Use_Spans,
               Call_Sites,
               Binding);
         when GM.Expr_Binary =>
            Walk_Expr
              (Expr.Left,
               Locals,
               Callable_Names,
               Signatures,
               Shared_Wrappers,
               Shared_Helper_Prefixes,
               Reads,
               Shared_Reads,
               Shared_Writes,
               Calls,
               Inputs,
               Outputs,
               Use_Spans,
               Call_Sites,
               Binding);
            Walk_Expr
              (Expr.Right,
               Locals,
               Callable_Names,
               Signatures,
               Shared_Wrappers,
               Shared_Helper_Prefixes,
               Reads,
               Shared_Reads,
               Shared_Writes,
               Calls,
               Inputs,
               Outputs,
               Use_Spans,
               Call_Sites,
               Binding);
         when GM.Expr_Allocator =>
            Walk_Expr
              (Expr.Value,
               Locals,
               Callable_Names,
               Signatures,
               Shared_Wrappers,
               Shared_Helper_Prefixes,
               Reads,
               Shared_Reads,
               Shared_Writes,
               Calls,
               Inputs,
               Outputs,
               Use_Spans,
               Call_Sites,
               Binding);
         when GM.Expr_Aggregate =>
            if not Expr.Fields.Is_Empty then
               for Field of Expr.Fields loop
                  Walk_Expr
                    (Field.Expr,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Reads,
                     Shared_Reads,
                     Shared_Writes,
                     Calls,
                     Inputs,
                     Outputs,
                     Use_Spans,
                     Call_Sites,
                     Binding);
               end loop;
            end if;
         when GM.Expr_Call =>
            Callee := FT.To_UString (Flatten_Name (Expr.Callee));
            if UString_Value (Callee) /= ""
              and then Try_Shared_Call
                (UString_Value (Callee),
                 Shared_Wrappers,
                 Shared_Helper_Prefixes,
                 Root_Name  => Shared_Root,
                 Operation  => Shared_Op)
            then
               Mark_Shared_Call
                 (Root_Name     => UString_Value (Shared_Root),
                  Operation     => UString_Value (Shared_Op),
                  Shared_Reads  => Shared_Reads,
                  Shared_Writes => Shared_Writes,
                  Inputs        => Inputs,
                  Outputs       => Outputs,
                  Use_Spans     => Use_Spans,
                  Span          => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span));
               if not Expr.Args.Is_Empty then
                  for Arg of Expr.Args loop
                     Walk_Expr
                       (Arg,
                        Locals,
                        Callable_Names,
                        Signatures,
                        Shared_Wrappers,
                        Shared_Helper_Prefixes,
                        Reads,
                        Shared_Reads,
                        Shared_Writes,
                        Calls,
                        Inputs,
                        Outputs,
                        Use_Spans,
                        Call_Sites,
                        Binding);
                  end loop;
               end if;
            elsif UString_Value (Callee) /= "" and then Callable_Names.Contains (UString_Value (Callee)) then
               Calls.Include (UString_Value (Callee));
               Note_Use_Span
                 (UString_Value (Callee),
                  (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
                  Use_Spans);
               if not Signatures.Contains (UString_Value (Callee)) then
                  Raise_Internal ("missing callable signature for `" & UString_Value (Callee) & "`");
               end if;

               declare
                  Signature : constant Callable_Signature := Signatures.Element (UString_Value (Callee));
                  Call      : Call_Site;
               begin
                  if Expr.Args.Length /= Signature.Param_Names.Length then
                     Raise_Internal
                       ("call arity mismatch for `" & UString_Value (Callee) & "`");
                  end if;

                  Call.Callee := Callee;
                  Call.Span := (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span);
                  if not Expr.Args.Is_Empty then
                     for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
                        declare
                           Mode         : constant String := UString_Value (Signature.Param_Modes (Index));
                           Actual_Input : aliased Marker_Binding;
                           Actual_Output : Marker_Binding;
                        begin
                           if Mode /= "out" then
                              Walk_Expr
                                (Expr.Args (Index),
                                 Locals,
                                 Callable_Names,
                                 Signatures,
                                 Shared_Wrappers,
                                 Shared_Helper_Prefixes,
                                 Reads,
                                 Shared_Reads,
                                 Shared_Writes,
                                 Calls,
                                 Inputs,
                                 Outputs,
                                 Use_Spans,
                                 Call_Sites,
                                 Actual_Input'Access);
                           end if;

                           if Mode in "mut" | "out" | "in out" then
                              Collect_Output_Binding
                                (Expr.Args (Index),
                                 Locals,
                                 Actual_Output);
                           end if;

                           Call.Input_Bindings.Append (Actual_Input);
                           Call.Output_Bindings.Append (Actual_Output);
                        end;
                     end loop;
                  end if;
                  Call_Sites.Append (Call);
               end;
            elsif not Expr.Args.Is_Empty then
               for Arg of Expr.Args loop
                  Walk_Expr
                    (Arg,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Reads,
                     Shared_Reads,
                     Shared_Writes,
                     Calls,
                     Inputs,
                     Outputs,
                     Use_Spans,
                     Call_Sites,
                     Binding);
               end loop;
            end if;
         when others =>
            null;
      end case;
   end Walk_Expr;

   function External_Summary
     (Value               : GM.External_Entry;
      Shared_Object_Names : String_Sets.Set) return Direct_Summary
   is
      Result : Direct_Summary;
   begin
      Result.Name := Value.Name;
      Result.Kind := Value.Kind;
      Result.Span := Value.Span;
      for Item of Value.Effect_Summary.Reads loop
         declare
            Name : constant String := UString_Value (Item);
         begin
            if Shared_Object_Names.Contains (Name) then
               Result.Direct_Shared_Reads.Include (Name);
            else
               Result.Direct_Reads.Include (Name);
            end if;
         end;
      end loop;
      for Item of Value.Effect_Summary.Writes loop
         declare
            Name : constant String := UString_Value (Item);
         begin
            if Shared_Object_Names.Contains (Name) then
               Result.Direct_Shared_Writes.Include (Name);
            else
               Result.Direct_Writes.Include (Name);
            end if;
         end;
      end loop;
      for Item of Value.Effect_Summary.Inputs loop
         Result.Direct_Inputs.Include (UString_Value (Item));
      end loop;
      for Item of Value.Effect_Summary.Outputs loop
         Result.Direct_Outputs.Include (UString_Value (Item));
      end loop;
      for Item of Value.Channel_Summary.Channels loop
         Result.Direct_Channels.Include (UString_Value (Item));
      end loop;
      for Item of Value.Channel_Summary.Sends loop
         Result.Direct_Sends.Include (UString_Value (Item));
      end loop;
      for Item of Value.Channel_Summary.Receives loop
         Result.Direct_Receives.Include (UString_Value (Item));
      end loop;
      if Result.Direct_Channels /= String_Sets.Empty_Set
        and then Result.Direct_Sends = String_Sets.Empty_Set
        and then Result.Direct_Receives = String_Sets.Empty_Set
      then
         Result.Direct_Legacy_Channels := Result.Direct_Channels;
      end if;
      Result.Reads := Result.Direct_Reads;
      Result.Writes := Result.Direct_Writes;
      Result.Shared_Reads := Result.Direct_Shared_Reads;
      Result.Shared_Writes := Result.Direct_Shared_Writes;
      Result.Channels := Result.Direct_Channels;
      Result.Sends := Result.Direct_Sends;
      Result.Receives := Result.Direct_Receives;
      Result.Legacy_Channels := Result.Direct_Legacy_Channels;
      Result.Calls := Result.Direct_Calls;
      Result.Inputs := Result.Direct_Inputs;
      Result.Outputs := Result.Direct_Outputs;
      return Result;
   end External_Summary;

   function Formal_Index
     (Signature   : Callable_Signature;
      Formal_Name : String) return Natural
   is
   begin
      if not Signature.Param_Names.Is_Empty then
         for Index in Signature.Param_Names.First_Index .. Signature.Param_Names.Last_Index loop
            if UString_Value (Signature.Param_Names (Index)) = Formal_Name then
               return Natural (Index);
            end if;
         end loop;
      end if;
      return 0;
   end Formal_Index;

   procedure Project_Call_Markers
     (Markers       : String_Sets.Set;
      Signature     : Callable_Signature;
      Bindings      : Marker_Binding_Vectors.Vector;
      Call_Span     : FT.Source_Span;
      Target        : in out String_Sets.Set;
      Target_Spans  : in out Span_Maps.Map;
      Ignore_Return : Boolean := False)
   is
      Cursor : String_Sets.Cursor := Markers.First;
   begin
      while String_Sets.Has_Element (Cursor) loop
         declare
            Marker : constant String := String_Sets.Element (Cursor);
         begin
            if Starts_With (Marker, "global:") then
               Target.Include (Marker);
               Note_Use_Span (Marker, Call_Span, Target_Spans);
            elsif Starts_With (Marker, "param:") then
               declare
                  Formal_Name : constant String := Marker (Marker'First + 6 .. Marker'Last);
                  Index       : constant Natural := Formal_Index (Signature, Formal_Name);
               begin
                  if Index = 0 then
                     Raise_Internal ("unknown formal marker `" & Marker & "` in Bronze summary propagation");
                  elsif Ada.Containers.Count_Type (Index) > Bindings.Length then
                     Raise_Internal ("parameter arity mismatch during Bronze summary projection");
                  else
                     declare
                        Binding      : constant Marker_Binding := Bindings (Positive (Index));
                        Marker_Cursor : String_Sets.Cursor := Binding.Markers.First;
                     begin
                        while String_Sets.Has_Element (Marker_Cursor) loop
                           declare
                              Bound_Marker : constant String := String_Sets.Element (Marker_Cursor);
                           begin
                              Target.Include (Bound_Marker);
                              if Binding.Use_Spans.Contains (Bound_Marker) then
                                 Note_Use_Span
                                   (Bound_Marker,
                                    Binding.Use_Spans.Element (Bound_Marker),
                                    Target_Spans);
                              else
                                 Note_Use_Span (Bound_Marker, Call_Span, Target_Spans);
                              end if;
                              String_Sets.Next (Marker_Cursor);
                           end;
                        end loop;
                     end;
                  end if;
               end;
            elsif Marker = "return" then
               if not Ignore_Return then
                  Raise_Internal ("unexpected return marker in Bronze call-input propagation");
               end if;
            else
               Raise_Internal ("malformed marker `" & Marker & "` in Bronze summary propagation");
            end if;
            String_Sets.Next (Cursor);
         end;
      end loop;
   end Project_Call_Markers;

   function Earliest_Task_Use_Span
     (Task_Names : FT.UString_Vectors.Vector;
      Summaries  : Summary_Maps.Map;
      Name       : String) return FT.Source_Span
   is
      Result : FT.Source_Span := FT.Null_Span;
   begin
      if not Task_Names.Is_Empty then
         for Task_Name of Task_Names loop
            declare
               Task_Key : constant String := UString_Value (Task_Name);
            begin
               if Summaries.Contains (Task_Key)
                 and then Summaries.Element (Task_Key).Use_Spans.Contains (Name)
               then
                  Result :=
                    Earlier_Span
                      (Result,
                       Summaries.Element (Task_Key).Use_Spans.Element (Name));
               end if;
            end;
         end loop;
      end if;
      return Result;
   end Earliest_Task_Use_Span;

   function Local_Use_Note (Span : FT.Source_Span) return String is
      function Pos_Image (Value : Positive) return String is
      begin
         return Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both);
      end Pos_Image;
   begin
      if not Has_Span (Span) then
         return "";
      end if;
      return
        "earliest local use at "
        & Pos_Image (Span.Start_Pos.Line)
        & ":"
        & Pos_Image (Span.Start_Pos.Column);
   end Local_Use_Note;

   function Dependency_Vector
     (Outputs : String_Sets.Set;
      Inputs  : String_Sets.Set) return Depends_Vectors.Vector
   is
      Result        : Depends_Vectors.Vector;
      Output_Items  : FT.UString_Vectors.Vector := To_Vector (Outputs);
      Input_Items   : constant FT.UString_Vectors.Vector := To_Vector (Inputs);
      Depends_Item  : Depends_Entry;
   begin
      if not Output_Items.Is_Empty then
         for Output_Name of Output_Items loop
            Depends_Item := (Output_Name => Output_Name, Inputs => Input_Items);
            Result.Append (Depends_Item);
         end loop;
      end if;
      return Result;
   end Dependency_Vector;

   function Find_Task_Index
     (Tasks : CM.Resolved_Task_Vectors.Vector;
      Name  : String) return Natural
   is
   begin
      if not Tasks.Is_Empty then
         for Index in Tasks.First_Index .. Tasks.Last_Index loop
            if UString_Value (Tasks (Index).Name) = Name then
               return Natural (Index);
            end if;
         end loop;
      end if;
      return 0;
   end Find_Task_Index;

   function Use_Span_For
     (Summary      : Direct_Summary;
      Channel_Name : String) return FT.Source_Span
   is
   begin
      if Summary.Use_Spans.Contains (Channel_Name) then
         return Summary.Use_Spans.Element (Channel_Name);
      end if;
      return Summary.Span;
   end Use_Span_For;

   function Contract_Note
     (Direction : String;
      Allowed   : String_Sets.Set) return String
   is
   begin
      if Allowed = String_Sets.Empty_Set then
         return "allowed `" & Direction & "` channels: <none>";
      end if;
      return
        "allowed `" & Direction & "` channels: "
        & Join_Strings (To_Vector (Allowed));
   end Contract_Note;

   function Summary_For
     (Graph      : GM.Graph_Entry;
      Callable_Names : String_Sets.Set;
      Signatures : Signature_Maps.Map;
      Init_Set   : in out String_Sets.Set;
      Global_Spans : in out Span_Maps.Map;
      Shared_Wrappers : Name_Maps.Map;
      Shared_Helper_Prefixes : Name_Maps.Map) return Direct_Summary
   is
      Result : Direct_Summary;
      Locals : constant Local_Maps.Map := Local_Metadata (Graph);
      Root   : FT.UString := FT.To_UString ("");
   begin
      Result.Name := Graph.Name;
      Result.Kind := Graph.Kind;
      Result.Is_Task := UString_Value (Graph.Kind) = "task";
      if Result.Is_Task and then Graph.Has_Priority then
         Result.Priority := Graph.Priority;
      end if;
      Result.Span := Graph.Span;

      for Local of Graph.Locals loop
         if UString_Value (Local.Kind) = "global"
           and then not Global_Spans.Contains (UString_Value (Local.Name))
         then
            Global_Spans.Include (UString_Value (Local.Name), Local.Span);
         end if;
      end loop;

      for Block of Graph.Blocks loop
         for Op of Block.Ops loop
            case Op.Kind is
               when GM.Op_Assign =>
                  Walk_Expr
                    (Op.Value,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Result.Direct_Reads,
                     Result.Direct_Shared_Reads,
                     Result.Direct_Shared_Writes,
                     Result.Direct_Calls,
                     Result.Direct_Inputs,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Result.Call_Sites);
                  Root := FT.To_UString (Root_Name (Op.Target));
                  if UString_Value (Root) /= ""
                    and then Locals.Contains (UString_Value (Root))
                    and then Op.Declaration_Init
                    and then UString_Value (Locals.Element (UString_Value (Root)).Kind) = "global"
                  then
                     Init_Set.Include (UString_Value (Root));
                  else
                     Note_Write
                       (UString_Value (Root),
                        Locals,
                        Result.Direct_Writes,
                        Result.Direct_Outputs,
                        Result.Use_Spans,
                        Op.Span);
                  end if;
               when GM.Op_Call =>
                  Walk_Expr
                    (Op.Value,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Result.Direct_Reads,
                     Result.Direct_Shared_Reads,
                     Result.Direct_Shared_Writes,
                     Result.Direct_Calls,
                     Result.Direct_Inputs,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Result.Call_Sites);
               when GM.Op_Channel_Send =>
                  Walk_Expr
                    (Op.Value,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Result.Direct_Reads,
                     Result.Direct_Shared_Reads,
                     Result.Direct_Shared_Writes,
                     Result.Direct_Calls,
                     Result.Direct_Inputs,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Result.Call_Sites);
                  Root := FT.To_UString (Flatten_Name (Op.Channel));
                  if UString_Value (Root) /= "" then
                     Result.Direct_Channels.Include (UString_Value (Root));
                     Result.Direct_Sends.Include (UString_Value (Root));
                     Note_Use_Span (UString_Value (Root), Op.Span, Result.Use_Spans);
                  end if;
               when GM.Op_Channel_Receive =>
                  Root := FT.To_UString (Flatten_Name (Op.Channel));
                  if UString_Value (Root) /= "" then
                     Result.Direct_Channels.Include (UString_Value (Root));
                     Result.Direct_Receives.Include (UString_Value (Root));
                     Note_Use_Span (UString_Value (Root), Op.Span, Result.Use_Spans);
                  end if;
                  Note_Write
                    (Root_Name (Op.Target),
                     Locals,
                     Result.Direct_Writes,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Op.Span);
               when GM.Op_Channel_Try_Send =>
                  Walk_Expr
                    (Op.Value,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Result.Direct_Reads,
                     Result.Direct_Shared_Reads,
                     Result.Direct_Shared_Writes,
                     Result.Direct_Calls,
                     Result.Direct_Inputs,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Result.Call_Sites);
                  Root := FT.To_UString (Flatten_Name (Op.Channel));
                  if UString_Value (Root) /= "" then
                     Result.Direct_Channels.Include (UString_Value (Root));
                     Result.Direct_Sends.Include (UString_Value (Root));
                     Note_Use_Span (UString_Value (Root), Op.Span, Result.Use_Spans);
                  end if;
                  Note_Write
                    (Root_Name (Op.Success_Target),
                     Locals,
                     Result.Direct_Writes,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Op.Span);
               when GM.Op_Channel_Try_Receive =>
                  Root := FT.To_UString (Flatten_Name (Op.Channel));
                  if UString_Value (Root) /= "" then
                     Result.Direct_Channels.Include (UString_Value (Root));
                     Result.Direct_Receives.Include (UString_Value (Root));
                     Note_Use_Span (UString_Value (Root), Op.Span, Result.Use_Spans);
                  end if;
                  Note_Write
                    (Root_Name (Op.Target),
                     Locals,
                     Result.Direct_Writes,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Op.Span);
                  Note_Write
                    (Root_Name (Op.Success_Target),
                     Locals,
                     Result.Direct_Writes,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Op.Span);
               when GM.Op_Delay =>
                  Walk_Expr
                    (Op.Value,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Result.Direct_Reads,
                     Result.Direct_Shared_Reads,
                     Result.Direct_Shared_Writes,
                     Result.Direct_Calls,
                     Result.Direct_Inputs,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Result.Call_Sites);
               when others =>
                  null;
            end case;
         end loop;

         case Block.Terminator.Kind is
            when GM.Terminator_Branch =>
               Walk_Expr
                 (Block.Terminator.Condition,
                  Locals,
                  Callable_Names,
                  Signatures,
                  Shared_Wrappers,
                  Shared_Helper_Prefixes,
                  Result.Direct_Reads,
                  Result.Direct_Shared_Reads,
                  Result.Direct_Shared_Writes,
                  Result.Direct_Calls,
                  Result.Direct_Inputs,
                  Result.Direct_Outputs,
                  Result.Use_Spans,
                  Result.Call_Sites);
            when GM.Terminator_Return =>
               if Block.Terminator.Has_Value then
                  Walk_Expr
                    (Block.Terminator.Value,
                     Locals,
                     Callable_Names,
                     Signatures,
                     Shared_Wrappers,
                     Shared_Helper_Prefixes,
                     Result.Direct_Reads,
                     Result.Direct_Shared_Reads,
                     Result.Direct_Shared_Writes,
                     Result.Direct_Calls,
                     Result.Direct_Inputs,
                     Result.Direct_Outputs,
                     Result.Use_Spans,
                     Result.Call_Sites);
                  Result.Direct_Outputs.Include ("return");
               end if;
            when GM.Terminator_Select =>
               if not Block.Terminator.Arms.Is_Empty then
                  for Arm of Block.Terminator.Arms loop
                     if Arm.Kind = GM.Select_Arm_Channel then
                        Result.Direct_Channels.Include
                          (UString_Value (Arm.Channel_Data.Channel_Name));
                        Result.Direct_Receives.Include
                          (UString_Value (Arm.Channel_Data.Channel_Name));
                        Note_Use_Span
                          (UString_Value (Arm.Channel_Data.Channel_Name),
                           Arm.Channel_Data.Span,
                           Result.Use_Spans);
                     elsif Arm.Kind = GM.Select_Arm_Delay then
                        Walk_Expr
                          (Arm.Delay_Data.Duration_Expr,
                           Locals,
                           Callable_Names,
                           Signatures,
                           Shared_Wrappers,
                           Shared_Helper_Prefixes,
                           Result.Direct_Reads,
                           Result.Direct_Shared_Reads,
                           Result.Direct_Shared_Writes,
                           Result.Direct_Calls,
                           Result.Direct_Inputs,
                           Result.Direct_Outputs,
                           Result.Use_Spans,
                           Result.Call_Sites);
                     end if;
                  end loop;
               end if;
            when others =>
               null;
         end case;
      end loop;

      Result.Reads := Result.Direct_Reads;
      Result.Writes := Result.Direct_Writes;
      Result.Shared_Reads := Result.Direct_Shared_Reads;
      Result.Shared_Writes := Result.Direct_Shared_Writes;
      Result.Channels := Result.Direct_Channels;
      Result.Sends := Result.Direct_Sends;
      Result.Receives := Result.Direct_Receives;
      Result.Calls := Result.Direct_Calls;
      Result.Inputs := Result.Direct_Inputs;
      Result.Outputs := Result.Direct_Outputs;
      return Result;
   end Summary_For;

   function Summary_Diagnostic
     (Path_String : String;
      Reason      : String;
      Message     : String;
      Span        : FT.Source_Span;
      Note_1      : String := "";
      Note_2      : String := "") return MD.Diagnostic
   is
      Result : MD.Diagnostic;
   begin
      Result.Reason := FT.To_UString (Reason);
      Result.Message := FT.To_UString (Message);
      Result.Path := FT.To_UString (Path_String);
      Result.Span := Span;
      Result.Has_Highlight_Span := True;
      Result.Highlight_Span := Span;
      if Note_1 /= "" then
         Result.Notes.Append (FT.To_UString (Note_1));
      end if;
      if Note_2 /= "" then
         Result.Notes.Append (FT.To_UString (Note_2));
      end if;
      return Result;
   end Summary_Diagnostic;

   function Summarize
     (Document    : GM.Mir_Document;
      Tasks       : CM.Resolved_Task_Vectors.Vector := CM.Resolved_Task_Vectors.Empty_Vector;
      Path_String : String := "";
      Objects     : CM.Resolved_Object_Decl_Vectors.Vector := CM.Resolved_Object_Decl_Vectors.Empty_Vector;
      Imported_Objects : CM.Imported_Object_Decl_Vectors.Vector := CM.Imported_Object_Decl_Vectors.Empty_Vector)
      return Bronze_Result
   is
      Result        : Bronze_Result;
      Callable_Names : String_Sets.Set;
      Signatures    : Signature_Maps.Map;
      Summaries     : Summary_Maps.Map;
      Global_Spans  : Span_Maps.Map;
      Init_Set      : String_Sets.Set;
      Task_Access   : Set_Maps.Map;
      Task_Calls    : Set_Maps.Map;
      Channel_Tasks : Set_Maps.Map;
      Shared_Tasks  : Set_Maps.Map;
      Channel_Base_Ceilings : Integer_Maps.Map;
      Shared_Base_Ceilings  : Integer_Maps.Map;
      Shared_Wrappers       : Name_Maps.Map;
      Shared_Helper_Prefixes : Name_Maps.Map;
      Imported_Shared_Names : String_Sets.Set;
      Changed       : Boolean := True;
      Cursor        : Summary_Maps.Cursor;
   begin
      for Graph of Document.Graphs loop
         Callable_Names.Include (UString_Value (Graph.Name));
         Signatures.Include (UString_Value (Graph.Name), Signature_For (Graph));
      end loop;

      for Decl of Objects loop
         if Decl.Is_Shared and then not Decl.Names.Is_Empty then
            declare
               Root_Name : constant String :=
                 UString_Value (Decl.Names (Decl.Names.First_Index));
            begin
               Shared_Wrappers.Include
                 (Canonical_Name (Shared_Wrapper_Object_Name (Root_Name)),
                  Root_Name);
               if Decl.Is_Public then
                  Shared_Helper_Prefixes.Include
                    (Canonical_Name
                       (Shared_Public_Helper_Base_Name (Root_Name) & "_"),
                     Root_Name);
               end if;
            end;
         end if;
      end loop;

      for Item of Imported_Objects loop
         if Item.Is_Shared then
            declare
               Qualified_Name : constant String := UString_Value (Item.Name);
               Package_Dot    : constant Natural :=
                 Ada.Strings.Fixed.Index
                   (Qualified_Name,
                    ".",
                    Ada.Strings.Backward);
               Package_Name   : constant String :=
                 (if Package_Dot > 1
                  then Qualified_Name (Qualified_Name'First .. Package_Dot - 1)
                  else "");
               Root_Name      : constant String := Tail_Name (Qualified_Name);
            begin
               Imported_Shared_Names.Include (Qualified_Name);
               if Item.Has_Required_Ceiling then
                  Shared_Base_Ceilings.Include
                    (Qualified_Name,
                     Item.Required_Ceiling);
               end if;
               if Package_Name /= "" then
                  Shared_Helper_Prefixes.Include
                    (Canonical_Name
                       (Package_Name
                        & "."
                        & Shared_Public_Helper_Base_Name (Root_Name)
                        & "_"),
                     Qualified_Name);
               end if;
            end;
         end if;
      end loop;

      for External of Document.Externals loop
         Callable_Names.Include (UString_Value (External.Name));
         Signatures.Include (UString_Value (External.Name), Signature_For (External));
         Summaries.Include
           (UString_Value (External.Name),
            External_Summary (External, Imported_Shared_Names));
      end loop;

      for Channel of Document.Channels loop
         if Channel.Has_Required_Ceiling then
            Channel_Base_Ceilings.Include (UString_Value (Channel.Name), Channel.Required_Ceiling);
         end if;
      end loop;

      for Graph of Document.Graphs loop
         declare
            Summary : constant Direct_Summary :=
              Summary_For
                (Graph,
                 Callable_Names,
                 Signatures,
                 Init_Set,
                 Global_Spans,
                 Shared_Wrappers,
                 Shared_Helper_Prefixes);
         begin
            Summaries.Include (UString_Value (Graph.Name), Summary);
         end;
      end loop;

      while Changed loop
         Changed := False;
         Cursor := Summaries.First;
         while Summary_Maps.Has_Element (Cursor) loop
            declare
               Name    : constant String := Summary_Maps.Key (Cursor);
               Summary : Direct_Summary := Summary_Maps.Element (Cursor);
               Updated : Direct_Summary := Summary;
            begin
               if not Summary.Call_Sites.Is_Empty then
                  for Call of Summary.Call_Sites loop
                     declare
                        Callee : constant String := UString_Value (Call.Callee);
                     begin
                        if Summaries.Contains (Callee) then
                           declare
                              Callee_Summary : constant Direct_Summary := Summaries.Element (Callee);
                              Signature      : constant Callable_Signature := Signatures.Element (Callee);
                           begin
                              Updated.Reads.Union (Callee_Summary.Reads);
                              Updated.Writes.Union (Callee_Summary.Writes);
                              Updated.Shared_Reads.Union (Callee_Summary.Shared_Reads);
                              Updated.Shared_Writes.Union (Callee_Summary.Shared_Writes);
                              Updated.Channels.Union (Callee_Summary.Channels);
                              Updated.Sends.Union (Callee_Summary.Sends);
                              Updated.Receives.Union (Callee_Summary.Receives);
                              Updated.Legacy_Channels.Union (Callee_Summary.Legacy_Channels);
                              Project_Call_Markers
                                (Callee_Summary.Inputs,
                                 Signature,
                                 Call.Input_Bindings,
                                 Call.Span,
                                 Updated.Inputs,
                                 Updated.Use_Spans);
                              Project_Call_Markers
                                (Callee_Summary.Outputs,
                                 Signature,
                                 Call.Output_Bindings,
                                 Call.Span,
                                 Updated.Outputs,
                                 Updated.Use_Spans,
                                 Ignore_Return => True);
                              Updated.Calls.Union (Callee_Summary.Calls);
                              declare
                                 Entity_Cursor : String_Sets.Cursor := Callee_Summary.Reads.First;
                              begin
                                 while String_Sets.Has_Element (Entity_Cursor) loop
                                    declare
                                       Entity_Name : constant String := String_Sets.Element (Entity_Cursor);
                                    begin
                                       if not Updated.Use_Spans.Contains (Entity_Name) then
                                          if Summary.Use_Spans.Contains (Callee) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Summary.Use_Spans.Element (Callee));
                                          elsif Callee_Summary.Use_Spans.Contains (Entity_Name) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Callee_Summary.Use_Spans.Element (Entity_Name));
                                          end if;
                                       end if;
                                       String_Sets.Next (Entity_Cursor);
                                    end;
                                 end loop;
                              end;
                              declare
                                 Entity_Cursor : String_Sets.Cursor := Callee_Summary.Writes.First;
                              begin
                                 while String_Sets.Has_Element (Entity_Cursor) loop
                                    declare
                                       Entity_Name : constant String := String_Sets.Element (Entity_Cursor);
                                    begin
                                       if not Updated.Use_Spans.Contains (Entity_Name) then
                                          if Summary.Use_Spans.Contains (Callee) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Summary.Use_Spans.Element (Callee));
                                          elsif Callee_Summary.Use_Spans.Contains (Entity_Name) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Callee_Summary.Use_Spans.Element (Entity_Name));
                                          end if;
                                       end if;
                                       String_Sets.Next (Entity_Cursor);
                                    end;
                                 end loop;
                              end;
                              declare
                                 Entity_Cursor : String_Sets.Cursor := Callee_Summary.Shared_Reads.First;
                              begin
                                 while String_Sets.Has_Element (Entity_Cursor) loop
                                    declare
                                       Entity_Name : constant String := String_Sets.Element (Entity_Cursor);
                                    begin
                                       if not Updated.Use_Spans.Contains (Entity_Name) then
                                          if Summary.Use_Spans.Contains (Callee) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Summary.Use_Spans.Element (Callee));
                                          elsif Callee_Summary.Use_Spans.Contains (Entity_Name) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Callee_Summary.Use_Spans.Element (Entity_Name));
                                          end if;
                                       end if;
                                       String_Sets.Next (Entity_Cursor);
                                    end;
                                 end loop;
                              end;
                              declare
                                 Entity_Cursor : String_Sets.Cursor := Callee_Summary.Shared_Writes.First;
                              begin
                                 while String_Sets.Has_Element (Entity_Cursor) loop
                                    declare
                                       Entity_Name : constant String := String_Sets.Element (Entity_Cursor);
                                    begin
                                       if not Updated.Use_Spans.Contains (Entity_Name) then
                                          if Summary.Use_Spans.Contains (Callee) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Summary.Use_Spans.Element (Callee));
                                          elsif Callee_Summary.Use_Spans.Contains (Entity_Name) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Callee_Summary.Use_Spans.Element (Entity_Name));
                                          end if;
                                       end if;
                                       String_Sets.Next (Entity_Cursor);
                                    end;
                                 end loop;
                              end;
                              declare
                                 Entity_Cursor : String_Sets.Cursor := Callee_Summary.Channels.First;
                              begin
                                 while String_Sets.Has_Element (Entity_Cursor) loop
                                    declare
                                       Entity_Name : constant String := String_Sets.Element (Entity_Cursor);
                                    begin
                                       if not Updated.Use_Spans.Contains (Entity_Name) then
                                          if Summary.Use_Spans.Contains (Callee) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Summary.Use_Spans.Element (Callee));
                                          elsif Callee_Summary.Use_Spans.Contains (Entity_Name) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Callee_Summary.Use_Spans.Element (Entity_Name));
                                          end if;
                                       end if;
                                       String_Sets.Next (Entity_Cursor);
                                    end;
                                 end loop;
                              end;
                              declare
                                 Call_Cursor_2 : String_Sets.Cursor := Callee_Summary.Calls.First;
                              begin
                                 while String_Sets.Has_Element (Call_Cursor_2) loop
                                    declare
                                       Entity_Name : constant String := String_Sets.Element (Call_Cursor_2);
                                    begin
                                       if not Updated.Use_Spans.Contains (Entity_Name) then
                                          if Callee_Summary.Use_Spans.Contains (Entity_Name) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Callee_Summary.Use_Spans.Element (Entity_Name));
                                          elsif Summary.Use_Spans.Contains (Callee) then
                                             Updated.Use_Spans.Include
                                               (Entity_Name,
                                                Summary.Use_Spans.Element (Callee));
                                          end if;
                                       end if;
                                       String_Sets.Next (Call_Cursor_2);
                                    end;
                                 end loop;
                              end;
                           end;
                        end if;
                     end;
                  end loop;
               end if;

               if Updated.Reads /= Summary.Reads
                 or else Updated.Writes /= Summary.Writes
                 or else Updated.Shared_Reads /= Summary.Shared_Reads
                 or else Updated.Shared_Writes /= Summary.Shared_Writes
                 or else Updated.Channels /= Summary.Channels
                 or else Updated.Sends /= Summary.Sends
                 or else Updated.Receives /= Summary.Receives
                 or else Updated.Legacy_Channels /= Summary.Legacy_Channels
                 or else Updated.Inputs /= Summary.Inputs
                 or else Updated.Outputs /= Summary.Outputs
                 or else Updated.Calls /= Summary.Calls
               then
                  Changed := True;
                  Summaries.Include (Name, Updated);
               end if;
               Summary_Maps.Next (Cursor);
            end;
         end loop;
      end loop;

      Cursor := Summaries.First;
      while Summary_Maps.Has_Element (Cursor) loop
         declare
            Summary : constant Direct_Summary := Summary_Maps.Element (Cursor);
            Item    : Graph_Summary;
         begin
            Item.Name := Summary.Name;
            Item.Kind := Summary.Kind;
            Item.Is_Task := Summary.Is_Task;
            Item.Priority := Summary.Priority;
            Item.Reads := To_Vector (Summary.Reads);
            Item.Writes := To_Vector (Summary.Writes);
            declare
               Shareds : String_Sets.Set := Summary.Shared_Reads;
            begin
               Shareds.Union (Summary.Shared_Writes);
               Item.Shareds := To_Vector (Shareds);
            end;
            Item.Channels := To_Vector (Summary.Channels);
            Item.Sends := To_Vector (Summary.Sends);
            Item.Receives := To_Vector (Summary.Receives);
            Item.Calls := To_Vector (Summary.Calls);
            Item.Inputs := To_Vector (Summary.Inputs);
            Item.Outputs := To_Vector (Summary.Outputs);
            Item.Depends := Dependency_Vector (Summary.Outputs, Summary.Inputs);
            Result.Graphs.Append (Item);

            if Summary.Is_Task then
               declare
                  Accessed : String_Sets.Set := Summary.Reads;
                  Shared_Accessed : String_Sets.Set := Summary.Shared_Reads;
               begin
                  Accessed.Union (Summary.Writes);
                  Shared_Accessed.Union (Summary.Shared_Writes);
                  if not Accessed.Is_Empty then
                     declare
                        Global_Cursor : String_Sets.Cursor := Accessed.First;
                     begin
                        while String_Sets.Has_Element (Global_Cursor) loop
                           declare
                              Global_Name : constant String := String_Sets.Element (Global_Cursor);
                           begin
                              if not Is_Synthetic_Attribute_Marker (Global_Name, Global_Spans) then
                                 declare
                                    Use_Span : constant FT.Source_Span := Use_Span_For (Summary, Global_Name);
                                 begin
                                    Result.Diagnostics.Append
                                      (Summary_Diagnostic
                                         (Path_String,
                                          "task_variable_ownership",
                                          "task '" & UString_Value (Summary.Name)
                                          & "' accesses package global '"
                                          & Global_Name
                                          & "'",
                                          Use_Span,
                                          "task bodies may use only locals and channels",
                                          Local_Use_Note (Use_Span)));
                                 end;
                              end if;
                              String_Sets.Next (Global_Cursor);
                           end;
                        end loop;
                     end;
                  end if;

                  if not Accessed.Is_Empty then
                     declare
                        Global_Cursor : String_Sets.Cursor := Accessed.First;
                     begin
                        while String_Sets.Has_Element (Global_Cursor) loop
                           declare
                              Global_Name : constant String := String_Sets.Element (Global_Cursor);
                              Owners      : String_Sets.Set;
                           begin
                              if not Is_Synthetic_Attribute_Marker (Global_Name, Global_Spans) then
                                 if Task_Access.Contains (Global_Name) then
                                    Owners := Task_Access.Element (Global_Name);
                                 end if;
                                 Owners.Include (UString_Value (Summary.Name));
                                 Task_Access.Include (Global_Name, Owners);
                              end if;
                              String_Sets.Next (Global_Cursor);
                           end;
                        end loop;
                     end;
                  end if;

                  if not Shared_Accessed.Is_Empty then
                     declare
                        Shared_Cursor : String_Sets.Cursor := Shared_Accessed.First;
                     begin
                        while String_Sets.Has_Element (Shared_Cursor) loop
                           declare
                              Shared_Name : constant String := String_Sets.Element (Shared_Cursor);
                              Shared_Task_Set : String_Sets.Set;
                           begin
                              if Shared_Tasks.Contains (Shared_Name) then
                                 Shared_Task_Set := Shared_Tasks.Element (Shared_Name);
                              end if;
                              Shared_Task_Set.Include (UString_Value (Summary.Name));
                              Shared_Tasks.Include (Shared_Name, Shared_Task_Set);
                              String_Sets.Next (Shared_Cursor);
                           end;
                        end loop;
                     end;
                  end if;

                  if not Summary.Calls.Is_Empty then
                     declare
                        Call_Cursor : String_Sets.Cursor := Summary.Calls.First;
                     begin
                        while String_Sets.Has_Element (Call_Cursor) loop
                           declare
                              Callee : constant String := String_Sets.Element (Call_Cursor);
                              Tasks  : String_Sets.Set;
                           begin
                              if Task_Calls.Contains (Callee) then
                                 Tasks := Task_Calls.Element (Callee);
                              end if;
                              Tasks.Include (UString_Value (Summary.Name));
                              Task_Calls.Include (Callee, Tasks);
                              String_Sets.Next (Call_Cursor);
                           end;
                        end loop;
                     end;
                  end if;

                  if not Summary.Channels.Is_Empty then
                     declare
                        Channel_Cursor : String_Sets.Cursor := Summary.Channels.First;
                     begin
                        while String_Sets.Has_Element (Channel_Cursor) loop
                           declare
                              Channel_Name : constant String := String_Sets.Element (Channel_Cursor);
                              Tasks        : String_Sets.Set;
                           begin
                              if Channel_Tasks.Contains (Channel_Name) then
                                 Tasks := Channel_Tasks.Element (Channel_Name);
                              end if;
                              Tasks.Include (UString_Value (Summary.Name));
                              Channel_Tasks.Include (Channel_Name, Tasks);
                              String_Sets.Next (Channel_Cursor);
                           end;
                        end loop;
                     end;
                  end if;
               end;
            end if;

            Summary_Maps.Next (Cursor);
         end;
      end loop;

      Result.Initializes := To_Vector (Init_Set);
      Sort_Strings (Result.Initializes);

      declare
         Access_Cursor : Set_Maps.Cursor := Task_Access.First;
      begin
         while Set_Maps.Has_Element (Access_Cursor) loop
            declare
               Global_Name : constant String := Set_Maps.Key (Access_Cursor);
               Tasks       : constant String_Sets.Set := Set_Maps.Element (Access_Cursor);
               Task_Names  : FT.UString_Vectors.Vector := To_Vector (Tasks);
            begin
               if Task_Names.Length > 1 then
                  Result.Diagnostics.Append
                    (Summary_Diagnostic
                       (Path_String,
                        "task_variable_ownership",
                        "package global '" & Global_Name & "' is accessed by multiple tasks",
                        (if Global_Spans.Contains (Global_Name)
                         then Global_Spans.Element (Global_Name)
                         else Earliest_Task_Use_Span (Task_Names, Summaries, Global_Name)),
                        "tasks accessing '" & Global_Name & "': " & Join_Strings (Task_Names),
                        Local_Use_Note (Earliest_Task_Use_Span (Task_Names, Summaries, Global_Name))));
               elsif Task_Names.Length = 1 then
                  Result.Ownership.Append
                    ((Global_Name => FT.To_UString (Global_Name),
                      Task_Name   => Task_Names (Task_Names.First_Index)));
               end if;
               Set_Maps.Next (Access_Cursor);
            end;
         end loop;
      end;

      declare
         Call_Cursor : Set_Maps.Cursor := Task_Calls.First;
      begin
         while Set_Maps.Has_Element (Call_Cursor) loop
            declare
               Callee      : constant String := Set_Maps.Key (Call_Cursor);
               Tasks       : constant String_Sets.Set := Set_Maps.Element (Call_Cursor);
               Task_Names  : FT.UString_Vectors.Vector := To_Vector (Tasks);
            begin
               if Task_Names.Length > 1 and then Summaries.Contains (Callee) then
                  declare
                     Summary : constant Direct_Summary := Summaries.Element (Callee);
                  begin
                     if not Summary.Reads.Is_Empty or else not Summary.Writes.Is_Empty then
                        declare
                           Globals      : String_Sets.Set := Summary.Reads;
                           Globals_List : FT.UString_Vectors.Vector;
                           Primary_Span : constant FT.Source_Span :=
                             Earliest_Task_Use_Span (Task_Names, Summaries, Callee);
                        begin
                           Globals.Union (Summary.Writes);
                           Globals_List := To_Vector (Globals);
                           Result.Diagnostics.Append
                             (Summary_Diagnostic
                                (Path_String,
                                 "task_variable_ownership",
                                 "subprogram '" & Callee & "' with package-global effects is reachable from multiple tasks",
                                 Primary_Span,
                                 "tasks reaching '" & Callee & "': " & Join_Strings (Task_Names),
                                 (if Has_Span (Summary.Span)
                                  then
                                    "imported declaration at "
                                    & Ada.Strings.Fixed.Trim
                                        (Positive'Image (Summary.Span.Start_Pos.Line), Ada.Strings.Both)
                                    & ":"
                                    & Ada.Strings.Fixed.Trim
                                        (Positive'Image (Summary.Span.Start_Pos.Column), Ada.Strings.Both)
                                    & "; package globals accessed by '" & Callee & "': "
                                    & Join_Strings (Globals_List)
                                  else
                                    "package globals accessed by '" & Callee & "': "
                                    & Join_Strings (Globals_List))));
                        end;
                     end if;
                  end;
               end if;
               Set_Maps.Next (Call_Cursor);
            end;
         end loop;
      end;

      declare
         Channel_Cursor : Set_Maps.Cursor := Channel_Tasks.First;
      begin
         while Set_Maps.Has_Element (Channel_Cursor) loop
            declare
               Channel_Name : constant String := Set_Maps.Key (Channel_Cursor);
               Tasks        : constant String_Sets.Set := Set_Maps.Element (Channel_Cursor);
               Task_Names   : FT.UString_Vectors.Vector := To_Vector (Tasks);
               Priority     : Long_Long_Integer := 0;
               Ceiling      : Ceiling_Entry;
            begin
               if not Task_Names.Is_Empty then
                  for Task_Name of Task_Names loop
                     if Summaries.Contains (UString_Value (Task_Name))
                       and then Summaries.Element (UString_Value (Task_Name)).Priority > Priority
                     then
                        Priority := Summaries.Element (UString_Value (Task_Name)).Priority;
                     end if;
                  end loop;
                  if Channel_Base_Ceilings.Contains (Channel_Name)
                    and then Channel_Base_Ceilings.Element (Channel_Name) > Priority
                  then
                     Priority := Channel_Base_Ceilings.Element (Channel_Name);
                  end if;
                  Ceiling.Channel_Name := FT.To_UString (Channel_Name);
                  Ceiling.Priority := Priority;
                  Ceiling.Task_Names := Task_Names;
                  Result.Ceilings.Append (Ceiling);
               end if;
               Set_Maps.Next (Channel_Cursor);
            end;
         end loop;
      end;

      declare
         Shared_Cursor : Set_Maps.Cursor := Shared_Tasks.First;
      begin
         while Set_Maps.Has_Element (Shared_Cursor) loop
            declare
               Shared_Name : constant String := Set_Maps.Key (Shared_Cursor);
               Tasks       : constant String_Sets.Set := Set_Maps.Element (Shared_Cursor);
               Task_Names  : FT.UString_Vectors.Vector := To_Vector (Tasks);
               Priority    : Long_Long_Integer := 0;
               Ceiling     : Shared_Ceiling_Entry;
            begin
               if not Task_Names.Is_Empty then
                  for Task_Name of Task_Names loop
                     if Summaries.Contains (UString_Value (Task_Name))
                       and then Summaries.Element (UString_Value (Task_Name)).Priority > Priority
                     then
                        Priority := Summaries.Element (UString_Value (Task_Name)).Priority;
                     end if;
                  end loop;
                  if Shared_Base_Ceilings.Contains (Shared_Name)
                    and then Shared_Base_Ceilings.Element (Shared_Name) > Priority
                  then
                     Priority := Shared_Base_Ceilings.Element (Shared_Name);
                  end if;
                  Ceiling.Shared_Name := FT.To_UString (Shared_Name);
                  Ceiling.Priority := Priority;
                  Ceiling.Task_Names := Task_Names;
                  Result.Shared_Ceilings.Append (Ceiling);
               end if;
               Set_Maps.Next (Shared_Cursor);
            end;
         end loop;
      end;

      if not Tasks.Is_Empty then
         Cursor := Summaries.First;
         while Summary_Maps.Has_Element (Cursor) loop
            declare
               Summary    : constant Direct_Summary := Summary_Maps.Element (Cursor);
               Task_Index : constant Natural :=
                 (if Summary.Is_Task
                  then Find_Task_Index (Tasks, UString_Value (Summary.Name))
                  else 0);
            begin
               if Task_Index /= 0 then
                  declare
                     Task_Info        : constant CM.Resolved_Task := Tasks (Positive (Task_Index));
                     Allowed_Sends    : constant String_Sets.Set := To_Set (Task_Info.Send_Contracts);
                     Allowed_Receives : constant String_Sets.Set := To_Set (Task_Info.Receive_Contracts);
                     Send_Cursor      : String_Sets.Cursor;
                     Receive_Cursor   : String_Sets.Cursor;
                     Legacy_Cursor    : String_Sets.Cursor;
                  begin
                     if Task_Info.Has_Send_Contract then
                        Send_Cursor := Summary.Sends.First;
                        while String_Sets.Has_Element (Send_Cursor) loop
                           declare
                              Channel_Name : constant String := String_Sets.Element (Send_Cursor);
                              Use_Span     : constant FT.Source_Span := Use_Span_For (Summary, Channel_Name);
                           begin
                              if not Allowed_Sends.Contains (Channel_Name) then
                                 Result.Diagnostics.Append
                                   (Summary_Diagnostic
                                      (Path_String,
                                       "task_channel_direction",
                                       "task '" & UString_Value (Summary.Name)
                                       & "' reaches send on channel '"
                                       & Channel_Name
                                       & "' outside its `sends` contract",
                                       Use_Span,
                                       Contract_Note ("sends", Allowed_Sends),
                                       Local_Use_Note (Use_Span)));
                              end if;
                              String_Sets.Next (Send_Cursor);
                           end;
                        end loop;
                     end if;

                     if Task_Info.Has_Receive_Contract then
                        Receive_Cursor := Summary.Receives.First;
                        while String_Sets.Has_Element (Receive_Cursor) loop
                           declare
                              Channel_Name : constant String := String_Sets.Element (Receive_Cursor);
                              Use_Span     : constant FT.Source_Span := Use_Span_For (Summary, Channel_Name);
                           begin
                              if not Allowed_Receives.Contains (Channel_Name) then
                                 Result.Diagnostics.Append
                                   (Summary_Diagnostic
                                      (Path_String,
                                       "task_channel_direction",
                                       "task '" & UString_Value (Summary.Name)
                                       & "' reaches receive on channel '"
                                       & Channel_Name
                                       & "' outside its `receives` contract",
                                       Use_Span,
                                       Contract_Note ("receives", Allowed_Receives),
                                       Local_Use_Note (Use_Span)));
                              end if;
                              String_Sets.Next (Receive_Cursor);
                           end;
                        end loop;
                     end if;

                     if Task_Info.Has_Send_Contract or else Task_Info.Has_Receive_Contract then
                        Legacy_Cursor := Summary.Legacy_Channels.First;
                        while String_Sets.Has_Element (Legacy_Cursor) loop
                           declare
                              Channel_Name : constant String := String_Sets.Element (Legacy_Cursor);
                              Needs_Regen  : constant Boolean :=
                                (Task_Info.Has_Send_Contract and then not Allowed_Sends.Contains (Channel_Name))
                                or else
                                (Task_Info.Has_Receive_Contract and then not Allowed_Receives.Contains (Channel_Name));
                              Use_Span     : constant FT.Source_Span := Use_Span_For (Summary, Channel_Name);
                           begin
                              if Needs_Regen then
                                 Result.Diagnostics.Append
                                   (Summary_Diagnostic
                                      (Path_String,
                                       "task_channel_direction_legacy_interface",
                                       "task '" & UString_Value (Summary.Name)
                                       & "' reaches channel '"
                                       & Channel_Name
                                       & "' through a legacy flat interface summary; regenerate the provider interface for directional `sends`/`receives` summaries",
                                       Use_Span,
                                       (if Task_Info.Has_Send_Contract
                                        then Contract_Note ("sends", Allowed_Sends)
                                        else Contract_Note ("receives", Allowed_Receives)),
                                       (if Task_Info.Has_Send_Contract and then Task_Info.Has_Receive_Contract
                                        then Contract_Note ("receives", Allowed_Receives)
                                        else Local_Use_Note (Use_Span))));
                              end if;
                              String_Sets.Next (Legacy_Cursor);
                           end;
                        end loop;
                     end if;
                  end;
               end if;
               Summary_Maps.Next (Cursor);
            end;
         end loop;
      end if;

      Sort_Graph_Summaries (Result.Graphs);
      Sort_Ownership (Result.Ownership);
      Sort_Ceilings (Result.Ceilings);
      Sort_Shared_Ceilings (Result.Shared_Ceilings);

      return Result;
   end Summarize;
end Safe_Frontend.Mir_Bronze;
