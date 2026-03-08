with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;

package body Safe_Frontend.Mir_Diagnostics is
   package US renames Ada.Strings.Unbounded;

   procedure Append_String_Array
     (Result : in out US.Unbounded_String;
      Items  : FT.UString_Vectors.Vector) is
   begin
      US.Append (Result, "[");
      if not Items.Is_Empty then
         for Index in Items.First_Index .. Items.Last_Index loop
            if Index > Items.First_Index then
               US.Append (Result, ",");
            end if;
            US.Append (Result, Safe_Frontend.Json.Quote (Items (Index)));
         end loop;
      end if;
      US.Append (Result, "]");
   end Append_String_Array;

   function To_Json
     (Diagnostics : Diagnostic_Vectors.Vector) return String
   is
      Result : US.Unbounded_String := US.To_Unbounded_String ("{");
   begin
      US.Append (Result, """format"":""diagnostics-v0"",");
      US.Append (Result, """diagnostics"":[");
      if not Diagnostics.Is_Empty then
         for Index in Diagnostics.First_Index .. Diagnostics.Last_Index loop
            declare
               Item : constant Diagnostic := Diagnostics (Index);
            begin
               if Index > Diagnostics.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append (Result, "{");
               US.Append
                 (Result,
                  """reason"":" & Safe_Frontend.Json.Quote (Item.Reason) & ",");
               US.Append
                 (Result,
                  """message"":" & Safe_Frontend.Json.Quote (Item.Message) & ",");
               US.Append
                 (Result,
                  """path"":" & Safe_Frontend.Json.Quote (Item.Path) & ",");
               US.Append
                 (Result,
                  """span"":" & Safe_Frontend.Json.Span_Object (Item.Span) & ",");
               if Item.Has_Highlight_Span then
                  US.Append
                    (Result,
                     """highlight_span"":"
                     & Safe_Frontend.Json.Span_Object (Item.Highlight_Span)
                     & ",");
               else
                  US.Append (Result, """highlight_span"":null,");
               end if;
               US.Append (Result, """notes"":");
               Append_String_Array (Result, Item.Notes);
               US.Append (Result, ",");
               US.Append (Result, """suggestions"":");
               Append_String_Array (Result, Item.Suggestions);
               US.Append (Result, "}");
            end;
         end loop;
      end if;
      US.Append (Result, "]}");
      return US.To_String (Result) & Ada.Characters.Latin_1.LF;
   end To_Json;
end Safe_Frontend.Mir_Diagnostics;
