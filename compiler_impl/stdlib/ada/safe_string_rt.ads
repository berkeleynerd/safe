pragma SPARK_Mode (On);

package Safe_String_RT is
   type Safe_String is private;

   Empty : constant Safe_String;

   function From_Literal (Value : String) return Safe_String
      with Global => null,
           Post => Length (From_Literal'Result) = Value'Length,
           Depends => (From_Literal'Result => Value);
   function Clone (Source : Safe_String) return Safe_String
      with Global => null,
           Post => Length (Clone'Result) = Length (Source),
           Depends => (Clone'Result => Source);
   procedure Copy (Target : in out Safe_String; Source : Safe_String)
      with Global => null,
           Always_Terminates,
           Post => Length (Target) = Length (Source),
           Depends => (Target => (Target, Source));
   procedure Free (Value : in out Safe_String)
      with Global => null,
           Always_Terminates,
           Post => Length (Value) = 0,
           Depends => (Value => Value);
   procedure Dispose (Value : in out Safe_String) renames Free;

   function To_String (Value : Safe_String) return String
      with Global => null,
           Post => To_String'Result'Length = Length (Value),
           Depends => (To_String'Result => Value);
   function Length (Value : Safe_String) return Natural
      with Global => null,
           Depends => (Length'Result => Value);
   function Slice (Value : Safe_String; Low, High : Natural) return Safe_String
      with Global => null,
           Post =>
             (if High < Low or else High = 0 or else Low = 0 or else High > Length (Value)
              then Length (Slice'Result) = 0
              else Length (Slice'Result) = High - Low + 1),
           Depends => (Slice'Result => (Value, Low, High));
   function Concat (Left, Right : Safe_String) return Safe_String
      with Global => null,
           Post =>
             Long_Long_Integer (Length (Concat'Result)) =
               Long_Long_Integer (Length (Left))
               + Long_Long_Integer (Length (Right)),
           Depends => (Concat'Result => (Left, Right));
   function Equal (Left, Right : Safe_String) return Boolean
      with Global => null,
           Post => Equal'Result = (To_String (Left) = To_String (Right)),
           --  Body is SPARK_Mode (Off); this postcondition is an assumed
           --  contract verified manually against the body, not discharged by
           --  GNATprove.
           Depends => (Equal'Result => (Left, Right));

private
   pragma SPARK_Mode (Off);
   type String_Access is access String;
   type Safe_String is record
      Data : String_Access := null;
   end record;
   Empty : constant Safe_String := (Data => null);
end Safe_String_RT;
