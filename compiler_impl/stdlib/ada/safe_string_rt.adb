with Ada.Unchecked_Deallocation;

package body Safe_String_RT is
   pragma SPARK_Mode (Off);
   procedure Free_String is new Ada.Unchecked_Deallocation (String, String_Access);

   function From_Literal (Value : String) return Safe_String is
      Result : Safe_String := Empty;
   begin
      if Value'Length > 0 then
         Result.Data := new String (1 .. Value'Length);
         Result.Data.all := Value;
      end if;
      return Result;
   end From_Literal;

   function Clone (Source : Safe_String) return Safe_String is
      Result : Safe_String := Empty;
   begin
      if Source.Data = null then
         return Empty;
      end if;
      Result.Data := new String (1 .. Source.Data'Length);
      Result.Data.all := Source.Data.all;
      return Result;
   end Clone;

   procedure Copy (Target : in out Safe_String; Source : Safe_String) is
      Snapshot : constant Safe_String := Clone (Source);
   begin
      Free (Target);
      Target := Snapshot;
   end Copy;

   procedure Free (Value : in out Safe_String) is
   begin
      if Value.Data /= null then
         Free_String (Value.Data);
      end if;
      Value := Empty;
   end Free;

   function To_String (Value : Safe_String) return String is
   begin
      if Value.Data = null then
         return "";
      end if;
      declare
         Result : String (1 .. Value.Data'Length);
      begin
         Result := Value.Data.all;
         return Result;
      end;
   end To_String;

   function Length (Value : Safe_String) return Natural is
   begin
      if Value.Data = null then
         return 0;
      end if;
      return Value.Data'Length;
   end Length;

   function Slice (Value : Safe_String; Low, High : Natural) return Safe_String is
      Slice_Low  : Positive;
      Slice_High : Positive;
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
      Slice_Low := Value.Data'First + Positive (Low) - 1;
      Slice_High := Value.Data'First + Positive (High) - 1;
      return From_Literal (Value.Data (Slice_Low .. Slice_High));
   end Slice;

   function Concat (Left, Right : Safe_String) return Safe_String is
   begin
      return From_Literal (To_String (Left) & To_String (Right));
   end Concat;

   function Equal (Left, Right : Safe_String) return Boolean is
   begin
      return To_String (Left) = To_String (Right);
   end Equal;
end Safe_String_RT;
