"use client"

import React, { useState} from "react";
import {format, parse} from "date-fns";
import {Calendar} from "@/components/ui/calendar";
import {Popover, PopoverContent, PopoverTrigger} from "@/components/ui/popover";
import {Button} from "@/components/ui/button";
import {ChevronDownIcon} from "lucide-react";
export function DobPicker({value,onChange}:{value:string, onChange: (v:string)=> void;}){
    const [open, setOpen] = useState(false);
  const date = value ? parse(value, "yyyy-MM-dd", new Date()) : undefined;
  // Year dropdown range, derived from today so it never goes stale.
  // A licence holder is at least 16, so anything younger is not a valid DOB.
  const thisYear = new Date().getFullYear();
  const oldest = new Date(thisYear - 90, 0);
  const youngest = new Date(thisYear - 16, 11);
  return (
    <Popover open={open} onOpenChange={setOpen}>
      {/* className mirrors the plain <input> classes in SubmitPanel so this field lines up with its neighbours */}
      <PopoverTrigger render={<Button variant={"outline"} data-empty={!date}
          className="h-auto w-full justify-between rounded-md border border-line px-3 py-2 text-left font-normal data-[empty=true]:text-muted-foreground focus-visible:ring-2 focus-visible:ring-thread focus-visible:ring-offset-1">
          {date ? format(date, "PPP") : <span>Pick a date</span>}
          <ChevronDownIcon data-icon="inline-end" />
      </Button>} />
      <PopoverContent className="w-auto p-0" align="start">
        <Calendar
          mode="single"
          // month + year become dropdowns instead of prev/next arrows - a 1975 birthday
          // is 2 clicks instead of 600 presses of "previous month"
          captionLayout="dropdown"
          startMonth={oldest}
          endMonth={youngest}
          selected={date}
          onSelect={(d) => {
              if (d) onChange(format(d,"yyyy-MM-dd"));
              setOpen(false)
          }}
          // open near a plausible birth year, not today, when nothing is picked yet
          defaultMonth={date ?? new Date(thisYear - 30, 0)}
        />
      </PopoverContent>
    </Popover>
  )
}
