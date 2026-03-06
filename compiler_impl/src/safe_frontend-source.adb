with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Safe_Frontend.Source is
   package US renames Ada.Strings.Unbounded;

   function Load (Path : String) return Source_File is
      File   : Ada.Text_IO.File_Type;
      Buffer : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (File => File, Mode => Ada.Text_IO.In_File, Name => Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            US.Append (Buffer, Line);
            if not Ada.Text_IO.End_Of_File (File) then
               US.Append (Buffer, Ada.Characters.Latin_1.LF);
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return
        (Path    => FT.To_UString (Path),
         Content => Buffer);
   end Load;
end Safe_Frontend.Source;
