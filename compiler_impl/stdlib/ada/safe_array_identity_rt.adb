with Ada.Unchecked_Deallocation;

package body Safe_Array_Identity_RT is
   pragma SPARK_Mode (Off);
   procedure Free_Array is new Ada.Unchecked_Deallocation (Element_Array, Element_Array_Access);

   function From_Array (Value : Element_Array) return Safe_Array is
      Result : Safe_Array := Empty;
      Target_Index : Positive := 1;
   begin
      if Value'Length = 0 then
         return Empty;
      end if;
      Result.Data := new Element_Array (1 .. Value'Length);
      for Index in Value'Range loop
         Result.Data (Target_Index) := Element_Ops.Clone (Value (Index));
         if Target_Index < Result.Data'Last then
            Target_Index := Target_Index + 1;
         end if;
      end loop;
      return Result;
   end From_Array;

   function Clone (Source : Safe_Array) return Safe_Array is
   begin
      if Source.Data = null then
         return Empty;
      end if;
      return From_Array (Source.Data.all);
   end Clone;

   procedure Copy (Target : in out Safe_Array; Source : Safe_Array) is
      Snapshot : constant Safe_Array := Clone (Source);
   begin
      Free (Target);
      Target := Snapshot;
   end Copy;

   procedure Free (Value : in out Safe_Array) is
   begin
      if Value.Data /= null then
         for Index in Value.Data'Range loop
            Element_Ops.Free (Value.Data (Index));
         end loop;
         Free_Array (Value.Data);
      end if;
      Value := Empty;
   end Free;

   function Element (Value : Safe_Array; Index : Positive) return Element_Type is
   begin
      return Element_Ops.Clone (Value.Data (Index));
   end Element;

   procedure Replace_Element
     (Value : in out Safe_Array;
      Index : Positive;
      Item  : Element_Type) is
   begin
      Element_Ops.Free (Value.Data (Index));
      Value.Data (Index) := Element_Ops.Clone (Item);
   end Replace_Element;

   function Slice (Value : Safe_Array; Low, High : Natural) return Safe_Array is
      Result : Safe_Array := Empty;
      Offset : Natural := 0;
   begin
      if Value.Data = null
        or else Low = 0
        or else High = 0
        or else High < Low
        or else Low > Value.Data'Length
        or else High > Value.Data'Length
      then
         return Empty;
      end if;
      Result.Data := new Element_Array (1 .. Positive (High - Low + 1));
      for Index in Positive (Low) .. Positive (High) loop
         Offset := Offset + 1;
         Result.Data (Positive (Offset)) := Element_Ops.Clone (Value.Data (Index));
      end loop;
      return Result;
   end Slice;

   function Concat (Left, Right : Safe_Array) return Safe_Array is
      Result : Safe_Array := Empty;
      Offset : Natural := 0;
   begin
      if Length (Left) + Length (Right) = 0 then
         return Empty;
      end if;
      Result.Data := new Element_Array (1 .. Positive (Length (Left) + Length (Right)));
      if Left.Data /= null then
         for Index in Left.Data'Range loop
            Offset := Offset + 1;
            Result.Data (Positive (Offset)) := Element_Ops.Clone (Left.Data (Index));
         end loop;
      end if;
      if Right.Data /= null then
         for Index in Right.Data'Range loop
            Offset := Offset + 1;
            Result.Data (Positive (Offset)) := Element_Ops.Clone (Right.Data (Index));
         end loop;
      end if;
      return Result;
   end Concat;
end Safe_Array_Identity_RT;
