export function secondsToSecAndMin(e: number){
    const m = Math.floor(e % 3600 / 60).toString().padStart(2,'0'),
          s = Math.floor(e % 60).toString().padStart(2,'0');
    
    return m + ':' + s;
    //return `${h}:${m}:${s}`;
}

export function secondsToSecMinHour(e: number){
    const h = Math.floor(e / 3600).toString().padStart(2,'0'),
          m = Math.floor(e % 3600 / 60).toString().padStart(2,'0'),
          s = Math.floor(e % 60).toString().padStart(2,'0');
    
    return h + ':' + m + ':' + s;
    return `${h}:${m}:${s}`;
}