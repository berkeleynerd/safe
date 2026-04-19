with Safe_Array_Identity_Ops;

generic
   with package Element_Ops is new Safe_Array_Identity_Ops (<>);
package Safe_Array_Identity_RT
  with SPARK_Mode => On
is
   subtype Element_Type is Element_Ops.Element;
   use type Element_Type;
   type Safe_Array is private;
   type Element_Array is array (Positive range <>) of Element_Type;

   Empty : constant Safe_Array;

   function From_Array (Value : Element_Array) return Safe_Array
      with Global => null,
           Post =>
             Length (From_Array'Result) = Value'Length
             and then
             (for all Index in Value'Range =>
                 Element (From_Array'Result, Positive (Index - Value'First + 1)) =
                   Value (Index)),
           Depends => (From_Array'Result => Value);
   function Clone (Source : Safe_Array) return Safe_Array
      with Global => null,
           Post =>
             Length (Clone'Result) = Length (Source)
             and then
             (for all Index in 1 .. Length (Source) =>
                 Element (Clone'Result, Positive (Index)) =
                   Element (Source, Positive (Index))),
           Depends => (Clone'Result => Source);
   procedure Copy (Target : in out Safe_Array; Source : Safe_Array)
      with Global => null,
           Always_Terminates,
           Post =>
             Length (Target) = Length (Source)
             and then
             (for all Index in 1 .. Length (Source) =>
                 Element (Target, Positive (Index)) =
                   Element (Source, Positive (Index))),
           Depends => (Target => (Target, Source));
   procedure Free (Value : in out Safe_Array)
      with Global => null,
           Always_Terminates,
           Post => Length (Value) = 0,
           Depends => (Value => Value);
   procedure Dispose (Value : in out Safe_Array) renames Free;

   function Length (Value : Safe_Array) return Natural
      with Global => null,
           Depends => (Length'Result => Value);
   function Element (Value : Safe_Array; Index : Positive) return Element_Type
      with Global => null,
           Pre => Index <= Length (Value),
           Depends => (Element'Result => (Value, Index));
   procedure Replace_Element
     (Value : in out Safe_Array;
      Index : Positive;
      Item  : Element_Type)
      with Global => null,
           Pre => Index <= Length (Value),
           Always_Terminates,
           Post =>
             Length (Value) = Length (Value'Old)
             and then Element (Value, Index) = Item
             and then
             (for all Offset in 1 .. Length (Value) =>
                 (if Positive (Offset) /= Index
                  then Element (Value, Positive (Offset)) =
                    Element (Value'Old, Positive (Offset)))),
           Depends => (Value => (Value, Index, Item));
   function Slice (Value : Safe_Array; Low, High : Natural) return Safe_Array
      with Global => null,
           Post =>
             (if Length (Value) = 0
               or else Low = 0
               or else High = 0
               or else High < Low
               or else High > Length (Value)
              then Length (Slice'Result) = 0
              else
                Length (Slice'Result) = High - Low + 1
                and then
                (for all Offset in 1 .. Length (Slice'Result) =>
                    Element (Slice'Result, Positive (Offset)) =
                      Element (Value, Positive (Low + Offset - 1)))),
           Depends => (Slice'Result => (Value, Low, High));
   function Concat (Left, Right : Safe_Array) return Safe_Array
      with Global => null,
           Post =>
             Long_Long_Integer (Length (Concat'Result)) =
               Long_Long_Integer (Length (Left))
               + Long_Long_Integer (Length (Right))
             and then
             (for all Index in 1 .. Length (Left) =>
                 Element (Concat'Result, Positive (Index)) =
                   Element (Left, Positive (Index)))
             and then
             (for all Index in 1 .. Length (Right) =>
                 Element
                   (Concat'Result, Positive (Length (Left) + Index)) =
                     Element (Right, Positive (Index))),
           Depends => (Concat'Result => (Left, Right));

private
   pragma SPARK_Mode (Off);
   type Element_Array_Access is access Element_Array;
   type Safe_Array is record
      Data : Element_Array_Access := null;
   end record;
   Empty : constant Safe_Array := (Data => null);
   function Length (Value : Safe_Array) return Natural is
     (if Value.Data = null then 0 else Value.Data'Length);
end Safe_Array_Identity_RT;
