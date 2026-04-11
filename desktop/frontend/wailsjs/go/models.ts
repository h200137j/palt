export namespace main {
	
	export class UpdateInfo {
	    isNewer: boolean;
	    latestVersion: string;
	    downloadUrl: string;
	    releaseNotes: string;
	
	    static createFrom(source: any = {}) {
	        return new UpdateInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.isNewer = source["isNewer"];
	        this.latestVersion = source["latestVersion"];
	        this.downloadUrl = source["downloadUrl"];
	        this.releaseNotes = source["releaseNotes"];
	    }
	}

}

export namespace models {
	
	export class HistoryFile {
	    name: string;
	    size: number;
	
	    static createFrom(source: any = {}) {
	        return new HistoryFile(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.size = source["size"];
	    }
	}
	export class HistoryEntry {
	    id: string;
	    partnerName: string;
	    files: HistoryFile[];
	    totalSize: number;
	    direction: string;
	    // Go type: time
	    timestamp: any;
	    status: string;
	    errorMessage: string;
	    durationMillis: number;
	
	    static createFrom(source: any = {}) {
	        return new HistoryEntry(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.partnerName = source["partnerName"];
	        this.files = this.convertValues(source["files"], HistoryFile);
	        this.totalSize = source["totalSize"];
	        this.direction = source["direction"];
	        this.timestamp = this.convertValues(source["timestamp"], null);
	        this.status = source["status"];
	        this.errorMessage = source["errorMessage"];
	        this.durationMillis = source["durationMillis"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	export class Peer {
	    id: string;
	    deviceName: string;
	    ipAddress: string;
	    port: number;
	    os: string;
	
	    static createFrom(source: any = {}) {
	        return new Peer(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.deviceName = source["deviceName"];
	        this.ipAddress = source["ipAddress"];
	        this.port = source["port"];
	        this.os = source["os"];
	    }
	}

}

