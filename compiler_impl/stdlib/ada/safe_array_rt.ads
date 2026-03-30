pragma SPARK_Mode (On);

generic
   type Element_Type is private;
   with function Default_Element return Element_Type;
   with function Clone_Element (Source : Element_Type) return Element_Type;
   with procedure Free_Element (Value : in out Element_Type);
package Safe_Array_RT is
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
           Post => Length (Clone'Result) = Length (Source),
           Depends => (Clone'Result => Source);
   procedure Copy (Target : in out Safe_Array; Source : Safe_Array)
      with Global => null,
           Always_Terminates,
           Post => Length (Target) = Length (Source),
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
   function Slice (Value : Safe_Array; Low, High : Natural) return Safe_Array
      with Global => null,
           Depends => (Slice'Result => (Value, Low, High));
   function Concat (Left, Right : Safe_Array) return Safe_Array
      with Global => null,
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
end Safe_Array_RT;
