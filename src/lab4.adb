with Ada.Text_IO;             use Ada.Text_IO;
with STM32.GPIO;              use STM32.GPIO;
with STM32.Board;             use STM32.Board;
with STM32.Device;            use STM32.Device;
with HAL.Bitmap;              use HAL.Bitmap;
with STM32.Timers;            use STM32.Timers;
with STM32.PWM;               use STM32.PWM;
with BMP_Fonts;
with Bitmapped_Drawing;
with Bitmap_Color_Conversion; use Bitmap_Color_Conversion;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

procedure Lab4 is

    PWM_Buzzer        : GPIO_Point renames PA4;
    PWM_Output_Timer  : Timer renames Timer_3;
    PWM_Output_Buzzer : PWM_Modulator;
    PWM_Output_AF     : constant STM32.GPIO_Alternate_Function := GPIO_AF_TIM3_2;
    PWM_Frequency     : constant := 7_000;  -- arbitrary

        procedure Buzzer_On is
    begin 
        PWM_Output_Buzzer.Set_Duty_Cycle (75);
    end Buzzer_On;

    procedure Buzzer_Off is
    begin 
        PWM_Output_Buzzer.Set_Duty_Cycle (0);
    end Buzzer_Off;

    procedure Initialize_PWM_Engine is
    begin
        --Pwm_Set_Period_And_Duty (1, 50, 0);
        Configure_PWM_Timer (PWM_Output_Timer'Access, PWM_Frequency);

        PWM_Output_Buzzer.Attach_PWM_Channel
           (Generator => PWM_Output_Timer'Access, Channel => Channel_1,
            Point     => PWM_Buzzer, PWM_AF => PWM_Output_AF);

        --PWM_Output_Buzzer.Set_Duty_Cycle (75);
        PWM_Output_Buzzer.Enable_Output;
    end Initialize_PWM_Engine;

    package Str renames Ada.Strings.Unbounded;

    -- LED GPIO Points
    LED_Red   : User_LED := PG13;
    LED_Green : User_LED := PG14;

    LEDs : GPIO_Points := LED_Red & LED_Green;

    Col1 : GPIO_Point := PC9;
    Col2 : GPIO_Point := PE4;
    Col3 : GPIO_Point := PE5;
    Col4 : GPIO_Point := PE6;

    Row1_state : Boolean := False;
    Row2_state : Boolean := False;
    Row3_state : Boolean := False;
    Row4_state : Boolean := False;

    Col1_state : Boolean := False;
    Col2_state : Boolean := False;
    Col3_state : Boolean := False;
    Col4_state : Boolean := False;

    Row1 : GPIO_Point := PC8;
    Row2 : GPIO_Point := PA8;
    Row3 : GPIO_Point := PG9;
    Row4 : GPIO_Point := PA9;

    Col_Pins : array (1 .. 4) of GPIO_Point := (Col1, Col2, Col3, Col4);
    Row_Pins : array (1 .. 4) of GPIO_Point := (Row1, Row2, Row3, Row4);

    --type Key_State is (Pressed, Released);
    type Key_State is (Rise, High, Low);
    type Key is record
        --E : Integer := 0;
        S : Key_State;
        C : Character;
    end record;

    type Keys_Array is array (Row_Pins'Range, Col_Pins'Range) of Key;

    Keys : Keys_Array :=
       ((Key'(Low, '1'), Key'(Low, '2'), Key'(Low, '3'), Key'(Low, 'A')),
        (Key'(Low, '4'), Key'(Low, '5'), Key'(Low, '6'), Key'(Low, 'B')),
        (Key'(Low, '7'), Key'(Low, '8'), Key'(Low, '9'), Key'(Low, 'C')),
        (Key'(Low, '*'), Key'(Low, '0'), Key'(Low, '#'), Key'(Low, 'D')));
    -- 1 2 3 a
    -- 4 5 6 b
    -- 7 8 9 c
    -- * 0 # d

    state    : Boolean         := False;
    Password : constant String := "789C";

    procedure High (This : in out GPIO_Point) renames STM32.GPIO.Clear;
    procedure Low (This : in out GPIO_Point) renames STM32.GPIO.Set;

    procedure Configure_Analog_Input (This : in out GPIO_Point) is
    begin
        Enable_Clock (This);
        Configure_IO (This, (Mode => Mode_In, Resistors => Floating));
    end Configure_Analog_Input;

    procedure Configure_Analog_Output (This : in out GPIO_Point) is
    begin
        Enable_Clock (This);
        Configure_IO
           (This,
            (Mode => Mode_Out, Output_Type => Push_Pull, Speed => Speed_100MHz,
             Resistors => Floating));
    end Configure_Analog_Output;

    procedure Update_LEDs (Is_Armed : Boolean) is
    begin
        if Is_Armed then
            Low (LED_Red);
            High (LED_Green);
        else
            High (LED_Red);
            Low (LED_Green);
        end if;
    end Update_LEDs;

    procedure Configure_LEDs is
    begin
        Configure_Analog_Output (LED_Red);
        Configure_Analog_Output (LED_Green);
        Update_LEDs (state);

    end Configure_LEDs;

    procedure Print_To_LCD (Str : String) is
        BG : constant Bitmap_Color := (Alpha => 255, others => 64);
        FG : constant Bitmap_Color := (Alpha => 255, others => 255);
    begin
        Display.Hidden_Buffer (1).Set_Source (BG);
        Display.Hidden_Buffer (1).Fill;

        Bitmapped_Drawing.Draw_String
           (Display.Hidden_Buffer (1).all, Start => (0, 0), Msg => Str,
            Font => BMP_Fonts.Font16x24, Foreground => FG, Background => BG);

        Display.Update_Layer (1, Copy_Back => True);
    end Print_To_LCD;

    function "+" (S : Str.Unbounded_String) return String is
    begin
        return Str.To_String (S);
    end "+";
    function "+" (S : String) return Unbounded_String is
    begin
        return Str.To_Unbounded_String (S);
    end "+";

    Output : Str.Unbounded_String := +"";

    procedure Update_Key (Row_Idx : Integer; Col_Idx : Integer) is
        S : Key_State := Keys (Row_Idx, Col_Idx).S;
    begin
        if not Set (Row_Pins (Row_Idx)) and S = Low then
            Keys (Row_Idx, Col_Idx).S := Rise;
        end if;
    end Update_Key;

    procedure Validate_Key (Row_Idx : Integer; Col_Idx : Integer) is
        S : Key_State := Keys (Row_Idx, Col_Idx).S;
    begin
        if not Set (Row_Pins (Row_Idx)) and S = Rise then
            Str.Append (Output, Keys (Row_Idx, Col_Idx).C);
            Keys (Row_Idx, Col_Idx).S := High;
        else
            if Set (Row_Pins (Row_Idx)) and S = High then
                Keys (Row_Idx, Col_Idx).S := Low;
            end if;
        end if;
    end Validate_Key;

    procedure Check_Password is
    begin
        if +Output = Password then
            --Buzzer_Off;
            state := True;
            Update_LEDs (state);
            Output := +""; -- Clear input after checking
            Print_To_LCD ("NOT ARMED");
        elsif Str.Length (Output) = 4 then
            Output := +""; -- Reset if incorrect length 4 and wrong
            Print_To_LCD ("ERROR");
        end if;
    end Check_Password;

    function Generate_Asterisks (Length : Natural) return String is
        Result : String (1 .. Length) := (others => '*');
    begin
        return Result;
    end Generate_Asterisks;


begin
    Configure_Analog_Input (Row1);
    Configure_Analog_Input (Row2);
    Configure_Analog_Input (Row3);
    Configure_Analog_Input (Row4);
    Configure_Analog_Output (Col1);
    Configure_Analog_Output (Col2);
    Configure_Analog_Output (Col3);
    Configure_Analog_Output (Col4);
    Configure_LEDs;
    Initialize_PWM_Engine;
    Buzzer_Off;
    Low (Col1);
    Low (Col2);
    Low (Col3);
    Low (Col4);
    Display.Initialize;
    Display.Initialize_Layer (1, ARGB_8888);
    Print_To_LCD ("ARMED"); -- Initially show ARMED
    --  Update_LEDs (True);
    loop
        for Col_Index in Col_Pins'Range loop
            High (Col_Pins (Col_Index));
            for Row_Index in Row_Pins'Range loop
                Update_Key (Row_Index, Col_Index);
            end loop;
            delay 0.02;
            for Row_Index in Row_Pins'Range loop
                Validate_Key (Row_Index, Col_Index);
            end loop;
            Low (Col_Pins (Col_Index));
        end loop;
        if Str.Length (Output) > 0 then
            Print_To_LCD (Generate_Asterisks (Str.Length (Output)));
        end if;
        Check_Password;
    end loop;
end Lab4;