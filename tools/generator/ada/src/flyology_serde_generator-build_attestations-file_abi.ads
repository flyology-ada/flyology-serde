with Interfaces.C;
with System;

private package Flyology_Serde_Generator.Build_Attestations.File_ABI is
   use type Interfaces.C.int;

   subtype C_Int is Interfaces.C.int;
   subtype C_Long is Interfaces.C.long;
   subtype C_Size is Interfaces.C.size_t;
   subtype Descriptor is C_Int;

   Invalid_Descriptor : constant Descriptor := Descriptor'(-1);

   type Object_Kind is (Unknown_Object, Directory_Object, Regular_Object, Other_Object)
   with Convention => C;
   for Object_Kind use
     (Unknown_Object => 0,
      Directory_Object => 1,
      Regular_Object => 2,
      Other_Object => 3);
   for Object_Kind'Size use C_Int'Size;

   function Open_Absolute_Directory (Path : System.Address) return Descriptor with
     Import,
     Convention => C,
     External_Name => "flyology_serde_snapshot_open_directory";

   function Open_Child_Directory
     (Parent : Descriptor; Name : System.Address) return Descriptor with
     Import,
     Convention => C,
     External_Name => "flyology_serde_snapshot_openat_directory";

   function Open_Child_Object
     (Parent : Descriptor; Name : System.Address) return Descriptor with
     Import,
     Convention => C,
     External_Name => "flyology_serde_snapshot_openat_object";

   function Read_Identity
     (From                    : Descriptor;
      Device                  : not null access Interfaces.Unsigned_64;
      Inode                   : not null access Interfaces.Unsigned_64;
      Size                    : not null access Interfaces.Integer_64;
      Modification_Second     : not null access Interfaces.Integer_64;
      Modification_Nanosecond : not null access Interfaces.Integer_64;
      Change_Second           : not null access Interfaces.Integer_64;
      Change_Nanosecond       : not null access Interfaces.Integer_64;
      Kind                    : not null access C_Int) return C_Int with
     Import,
     Convention => C,
     External_Name => "flyology_serde_snapshot_fstat";

   function Read
     (From : Descriptor; Into : System.Address; Length : C_Size) return C_Long with
     Import,
     Convention => C,
     External_Name => "read";

   function Close (Target : Descriptor) return C_Int with
     Import,
     Convention => C,
     External_Name => "close";
   --  A failed close has platform-defined EINTR ambiguity and is never retried.

   function Current_Errno return C_Int with
     Import,
     Convention => C,
     External_Name => "flyology_serde_build_current_errno";

   function Errno_Interrupted return C_Int with
     Import,
     Convention => C,
     External_Name => "flyology_serde_build_errno_interrupted";
end Flyology_Serde_Generator.Build_Attestations.File_ABI;
