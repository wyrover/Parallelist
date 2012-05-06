class Task
{
    __new(ByRef data, length = -1)
    {
        if IsObject(data)
            data := LSON(data), length := -1
        
        if length < 0
            this.length := StrLen(data) * (A_IsUnicode + 1)
        else
            this.length := length
        
        this.SetCapacity("data", length)
        DllCall("RtlMoveMemory", "UPtr", this.getAddress("data"), "UPtr", &data, "UPtr", this.length)
    }
}
