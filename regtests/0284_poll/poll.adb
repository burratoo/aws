------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                        Copyright (C) 2016, AdaCore                       --
--                                                                          --
--  This is free software;  you can redistribute it  and/or modify it       --
--  under terms of the  GNU General Public License as published  by the     --
--  Free Software  Foundation;  either version 3,  or (at your option) any  --
--  later version.  This software is distributed in the hope  that it will  --
--  be useful, but WITHOUT ANY WARRANTY;  without even the implied warranty --
--  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU     --
--  General Public License for  more details.                               --
--                                                                          --
--  You should have  received  a copy of the GNU General  Public  License   --
--  distributed  with  this  software;   see  file COPYING3.  If not, go    --
--  to http://www.gnu.org/licenses for a complete copy of the license.      --
------------------------------------------------------------------------------

with Ada.Streams;         use Ada.Streams;
with Ada.Text_IO;         use Ada.Text_IO;
with AWS.Net.Poll_Events; use AWS.Net;
with AWS.Net.Std;

procedure Poll is
   Set : Poll_Events.Set (39);
   Ss  : array (1 .. Set.Size) of Std.Socket_Type;
   Local : constant String := Localhost (IPv6_Available);
   Count : Integer;
   Idx   : Positive;
   State : Event_Set;
   Data  : Stream_Element_Array (1 .. 32);
   Last  : Stream_Element_Offset;
begin
   Ss (1).Bind (Host => Local, Port => 0);
   Ss (1).Listen;
   Set.Add (Ss (1).Get_FD, (Input => True, others => False));

   ------------------
   -- Connect loop --
   ------------------

   for J in 2 .. Set.Size / 2 + 1 loop
      Ss (J).Connect (Local, Port => Ss (1).Get_Port, Wait => False);
      Set.Add (Ss (J).Get_FD, (Output => True, others => False));
   end loop;

   Put_Line ("Connection");

   -----------------
   -- Accept loop --
   -----------------

   loop
      Set.Wait (0.5, Count);

      Idx := 1;

      while Count > 0 loop
         Set.Next (Idx);
         exit when Idx > Set.Length;
         Count := Count - 1;

         State := Set.Status (Idx);

         if State = (Input .. Output => True) then
            Put_Line ("Unexpected state");

         elsif State (Output) then
            Set.Set_Mode (Idx, (Input => True, others => False));

         elsif State (Input) then
            if Idx /= 1 then
               Put_Line ("Unexpected input index");
            end if;

            Std.Accept_Socket (Ss (1), Ss (Set.Length + 1));
            Set.Add
              (Ss (Set.Length + 1).Get_FD, (Input => True, others => False));
         end if;

         Idx := Idx + 1;
      end loop;

      if Count /= 0 then
         Put_Line ("Wrong sockets event count " & Count'Img);
         exit;
      end if;

      exit when Set.Length = Ss'Length;
   end loop;

   Put_Line ("Connected");

   ----------------------------------
   -- Write over whole sockets set --
   ----------------------------------

   for J in 2 .. Ss'Last loop
      Ss (J).Send ((1 => Stream_Element (J)));

      Set.Wait (0.5, Count);

      if Count /= 1 then
         Put_Line ("Unexpected number of activated sockets");
      end if;

      Idx := 1;
      Set.Next (Idx);

      State := Set.Status (Idx);

      if State /= (Input => True, Output => False, Error => False) then
         Put_Line ("Unexpected state");
      end if;

      Ss (Idx).Receive (Data, Last);

      if Last /= Data'First then
         Put_Line ("Unexpected received data length");
      end if;

      if Integer (Data (Data'First)) /= J then
         Put_Line ("Unexpected received content");
      end if;
   end loop;

   Put_Line ("Transmitted");

   for J in 2 .. Ss'Last loop
      Ss (J).Send ((1 .. Data'Length + 8 => Stream_Element (J)));
      Ss (J).Set_Timeout (2.0);
   end loop;

   -------------------------------------------
   -- Test waiting neither Input nor Output --
   -------------------------------------------

   loop
      Set.Wait (0.25, Count);

      exit when Count = 0;

      Idx := 1;

      while Count > 0 loop
         Set.Next (Idx);
         exit when Idx > Set.Length;
         Count := Count - 1;

         State := Set.Status (Idx);

         if State /= (Input => True, Output => False, Error => False) then
            Put_Line ("Unexpected state");
            exit;
         end if;

         Ss (Idx).Receive (Data, Last);

         Put (if Last = Data'Last then "@" else Last'Img);

         if Idx rem 2 = 0 then
            Set.Set_Event (Idx, Input, False);
         end if;

         Idx := Idx + 1;
      end loop;
   end loop;

   New_Line;

end Poll;