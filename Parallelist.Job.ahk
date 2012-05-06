class Job {
    Working := False ;wip: not sure if still needed
    Queue := []
    QueuePos := 1
    Result := []
    Workers := { Idle: [], Active: [] }
    
    __new(ScriptCode)
    {
        ParallelistInitializeMessageHandler()
        this.ScriptCode := Parallelist.Worker.GetTemplate(ScriptCode)
    }
    
    __delete()
    {
        this.Stop()
        CloseError := 0
        
        This.Workers.Idle := [] ; let worker handle its' own deletion
        This.Working := False
    }
    
    AddWorker()
    {   ;returns 1 on error, 0 otherwise
        worker := new Parallelist.Worker(this, this.ScriptCode)
        If !IsObject(worker)
            Return, 1
        this.Workers.Idle[worker.hwnd] := worker
        Return, 0
    }
    
    RemoveWorker()
    {
        Return, !IsObject(This.Worker.Idle.Remove())
    }
    
    Start()
    {
        This.Working := 1
        this.CheckQueue()
    }
    
    Stop()
    {
        ;wip: send a message to the workers notifying that the job is to be stopped
        ; For hWorker In This.Workers.Active
        This.Working := 0
    }
    
    WaitFinish() {
        while this.Working
            Sleep 10
    }
    
    ReceiveResult(worker, ByRef Result, Length)
    {
        this.Workers.Idle.Insert(this.Workers.Remove(worker.hwnd))
        MsgBox % StrGet(&Result,Length)
        CheckQueue()
    }
    
    CheckQueue()
    {
        while this.Queue.MaxIndex() >= this.QueuePos && this.Workers.Idle.MaxIndex()
        {
            task := this.Queue[this.QueuePos]
            if !IsObject(task) || task.__class != "Parallelist.Task"
                task := new Parallelist.Task(task)
            worker := this.Workers.Idle.Remove()
            this.Workers.Active[worker.hwnd] := worker
            if worker.SendData(task)
                break
        }
        if (this.QueuePos >= this.Queue.MaxIndex())
            this.Working := False
    }
}