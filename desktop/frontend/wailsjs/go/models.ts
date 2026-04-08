export namespace models {
	
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

