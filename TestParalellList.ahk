#Include Parallelist

ScriptCode = 
(
    WorkerInitialize()
    {   ;returns 1 on error, 0 otherwise
        Return, 0
    }
    
    WorkerProcess(Parallelist)
    {   ;returns 1 on error, 0 otherwise
        Parallelist.Output := "Worker has completed the task:``n``n""" . Parallelist.Data . """"
        Return, 0
    }
    
    WorkerUninitialize()
    {   ;returns 1 on error, 0 otherwise
        Return, 0
    }
)

Counter := 0
Job := new Parallelist.Job(ScriptCode)

Loop, 3
    Job.AddWorker()
Job.RemoveWorker()

Job.Queue := Array("task1","task2","task3","task4","task5","task6","task7","task8","task9")
Job.Start()
Job.WaitFinish()

For Index, Value In Job.Result
    MsgBox Index: %Index%`nValue: %Value%

Job.Stop()
Job.Close()
ExitApp

Tab::
    Counter++, Temp1 := "Something" . Counter
    ParallelistAssignTask(Job, Counter, Temp1, StrLen(Temp1) * (1 + A_IsUnicode))
Return

Esc::
    Job.Close()
ExitApp
