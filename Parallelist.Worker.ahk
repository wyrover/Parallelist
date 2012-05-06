class Worker
{
    static WorkerIndex := 0
    static Messages := []
    hwnd := 0
    currentTask := 0
    
    __new(Job, ScriptCode) ;job object, worker code, variable to receive the worker handle
    {
        WorkerIndex++
        PipeName := "\\.\pipe\ParallelistWorker" . WorkerIndex
        hPipe1 := DllCall("CreateNamedPipe","Str",PipeName,"UInt",2,"UInt",0,"UInt",255,"UInt",0,"UInt",0,"UInt",0,"UInt",0) ;temporary pipe
        hPipe2 := DllCall("CreateNamedPipe","Str",PipeName,"UInt",2,"UInt",0,"UInt",255,"UInt",0,"UInt",0,"UInt",0,"UInt",0) ;executable pipe
        
        CodePage := A_IsUnicode ? 1200 : 65001 ;UTF-16 or UTF-8
        Run, % """" . A_AhkPath . """ /CP" . CodePage . " """ . PipeName . """ " . A_ScriptHwnd . " " . &Job,, UseErrorLevel, WorkerPID ;run the script with the window and job ID as the parameter
        If ErrorLevel ;could not run the script
        {
            DllCall("CloseHandle","UPtr",hPipe1), DllCall("CloseHandle","UPtr",hPipe2) ;close the created pipes
            Return, 1
        }
        
        DllCall("ConnectNamedPipe","UPtr",hPipe1,"UPtr",0)
        DllCall("CloseHandle","UPtr",hPipe1) ;use temporary pipe
        
        DllCall("ConnectNamedPipe","UPtr",hPipe2,"UPtr",0)
        DllCall("WriteFile","UPtr",hPipe2,"UPtr",&ScriptCode,"UInt",StrLen(ScriptCode) * (A_IsUnicode + 1),"UPtr",0,"UPtr",0)
        DllCall("CloseHandle","UPtr",hPipe2) ;send the script code
        
        DetectHidden := A_DetectHiddenWindows
        DetectHiddenWindows, On ;need to detect a hidden window
        WinWait, ahk_pid %WorkerPID%,, 5 ;wait up to five seconds for the script to start
        this.hwnd := WinExist("ahk_pid " . WorkerPID) + 0 ;retrieve the worker ID
        DetectHiddenWindows, %DetectHidden%
        
        If !this.hwnd ;could not find the worker window
        {
            Process, Close, %WorkerPID%
            Return, 1
        }
    }
    
    __delete() {
        DetectHidden := A_DetectHiddenWindows
        
        DetectHiddenWindows, On ;need to detect a hidden window
        WinClose, % "ahk_id" this.hWorker ;send the WM_CLOSE message to the worker to allow it to execute any OnExit routines
        WinWaitClose, % "ahk_id" this.hWorker,, 1
        CloseError := ErrorLevel
        
        DetectHiddenWindows, %DetectHidden%
        Return, CloseError
    }
    
    HandleMessage(pCopyDataStruct)
    {
        Critical
        
        Message := {}
        Message.WorkerHWND := this
        Message.Job := Object(NumGet(pCopyDataStruct+0)) ;retrieve the job object from the pointer given
        Message.Length := NumGet(pCopyDataStruct+0, A_PtrSize, "UInt") ;retrieve the length of the data
        Message.SetCapacity("Data", Message.Length)
        
        DllCall("RtlMoveMemory", "UPtr", Message.getAddress("Data"), "UPtr", NumGet(pCopyDataStruct, A_PtrSize + 4), "UPtr", Message.Length) ;copy the data from the structure
        
        Parallelist.Worker.Messages.Insert(Message)
        
        SetTimer, ParallelistHandleWorkerMessage, -0
        Return, 1 ;successfully processed result
        
        ParallelistHandleWorkerMessage:
            Thread, NoTimers
            while Parallelist.Worker.Messages.MaxIndex()
            {
                ; get a copy to avoid collisions with HandleMessage. (shallow clone)
                cMessages := Parallelist.Worker.Messages.Clone()
                For i, msg in cMessages
                    msg.Job.ReceiveResult(msg.WorkerHWND
                Parallelist.Worker.Messages.Remove(1, cMessages.MaxIndex())
            }
        Return
    }
    
    SendData(Address, DataSize) ;window ID, number to be sent, data to be sent, length of the data in bytes
    { ;returns 1 on send failure, 0 otherwise
        VarSetCapacity(CopyData, 4 + A_PtrSize * 2, 0) ;COPYDATASTRUCT contains an integer field and two pointer sized fields
        NumPut(DataSize , CopyData, A_PtrSize, "UInt") ;insert the length of the data to be sent
        NumPut(Address+0, CopyData, A_PtrSize + 4)     ;insert the address of the data to be sent
        
        DetectHidden := A_DetectHiddenWindows
        DetectHiddenWindows, On                        ;hidden window detection required to send the message
        SendMessage, 0x4A, 0, &CopyData,, % "ahk_id" this.hWorker ;send the WM_COPYDATA message to the window
        DetectHiddenWindows, %DetectHidden%
        
        If (ErrorLevel = "FAIL") ;could not send the message
            Return, 1
        Return, 0
    }
    
    GetTemplate(ScriptCode)
    {
        Static Code = 
        (LTrim %
                ;#NoTrayIcon ;wip: debug
        
                ParallelistMainWindowID = %1% ;retrieve the window ID of the main script
                ParallelistJobID = %2% ;retrieve the job ID
                
                Parallelist := Object("Data",""
                ,"DataLength",0
                ,"Output",""
                ,"OutputLength",0)
                OnMessage(0x4A,"ParallelistReceiveData") ;WM_COPYDATA
                OnExit, ParallelistWorkerExitHook
                WorkerInitialize() ;call the user defined initialization function
            Return
            
            ;incoming message handler
            ParallelistReceiveData(wParam,lParam)
            {
                global Parallelist
                Critical
                Length := NumGet(lParam + A_PtrSize,0,"UInt") ;retrieve the length of the data
            
                Parallelist.SetCapacity("Data",Length)
                Parallelist.DataLength := Length ;allocate memory and store the length of the data
                DllCall("RtlMoveMemory","UPtr",Parallelist.GetAddress("Data"),"UPtr",NumGet(lParam + A_PtrSize + 4),"UPtr",Length) ;copy the data from the structure
                
                SetTimer, ParallelistWorkerTaskHook, -0 ;dispatch a subroutine to handle the task processing
                Return, 1 ;successfully processed data ;wip: allow errors to be returned to the main script
            }
            
            ParallelistSendResult(hWindow,JobID,pData,Length)
            {
                VarSetCapacity(CopyData, 4 + A_PtrSize * 2, 0) ;COPYDATASTRUCT contains an integer field and two pointer sized fields
                NumPut(JobID , CopyData)                       ;insert the length of the data to be sent
                NumPut(Length, CopyData, A_PtrSize, "UInt")    ;insert the length of the data to be sent
                NumPut(pData , CopyData, 4 + A_PtrSize)        ;insert the address of the data to be sent
                
                DetectHidden := A_DetectHiddenWindows
                DetectHiddenWindows, On ;hidden window detection required to send the message
                SendMessage, 0x4A, A_ScriptHwnd, &CopyData,, ahk_id %hWindow% ;send the WM_COPYDATA message to the window
                DetectHiddenWindows, %DetectHidden%
                
                If (ErrorLevel = "FAIL") ;could not send the message
                    Return, 1
                Return, 0
            }
            
            ParallelistWorkerTaskHook:
                Parallelist.OutputLength := -1 ;autodetect length
                WorkerProcess(Parallelist) ;call the user defined processing function
                ParallelistSendResult(ParallelistMainWindowID, ParallelistJobID, Parallelist.GetAddress("Output"), (Parallelist.OutputLength >= 0) ? Parallelist.OutputLength : StrLen(Parallelist.Output))
            Return
            
            ParallelistWorkerExitHook:
                WorkerUninitialize() ;call the user defined uninitialization function
            ExitApp
            
        )
        Return, Code`n%ScriptCode%
    }
}
