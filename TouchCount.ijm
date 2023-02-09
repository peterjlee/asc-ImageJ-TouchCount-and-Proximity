/*	ImageJ Macro to count the number of unique objects touching the each object
	Uniqueness is guaranteed by G. Landini's binary labeling plugin (part of "Morphology" package
	Uses histogram macro functions so that no additional particle analysis is required.
	Assumes that touching objects have been separated by one pixel.
	5/31/2016 10:50 AM Peter J. Lee (NHMFL) 
*/
	start = getTime(); // start timer after last requester for debugging
	setBatchMode(true);
	saveSettings(); /* To restore settings at the end */
	if (!checkForPlugin("morphology_collection.jar")) exit("Sorry, this macro requires G. Landini Morphology plugins: 8-way connected ")
	run("Options...", "iterations=1 count=1 black do=Nothing"); /* The binary count setting is set to "1" for consistent outlines */
	TitleOriginalBinaryImage = getTitle();
	if (roiManager("count")==0) 
		restoreExit("An existing ROI set must be loaded into the ROI manager.");
	imageWidth = getWidth();
	imageHeight = getHeight();
	if (is("binary")==0) 
		restoreExit("Needs to work from binary image.");
	/* Make sure white objects on black background for consistency */
	if (((getPixel(0, 0))!=0 || (getPixel(0, 1))!=0 || (getPixel(1, 0))!=0 || (getPixel(1, 1))!=0))
		run("Invert"); 
	/* Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this. */
	/* i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
	if (((getPixel(0, 0))+(getPixel(0, 1))+(getPixel(1, 0))+(getPixel(1, 1))) != 0) 
		restoreExit("Border Issue"); 	
	run("BinaryLabel", "white");  /* Requires G. Landini Morphology plugins: 8-way connected */
	TitleGrayLabeledImage = getTitle();
	roiOriginalCount = roiManager("count");
	showStatus("Looping through all " + roiOriginalCount + " objects for touching neighbors . . .");
	for (i=0 ; i<roiOriginalCount; i++) {
		showProgress(-i, roiManager("count"));
		selectWindow(TitleGrayLabeledImage);
		roiManager("select", i);
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		/* Expand ROI to include touching objects */
		roiManager("select", i);
		run("Enlarge...", "enlarge=2");
		run("Copy");
		newImage("pixelTouches","16-bit black",Rwidth+8,Rheight+8,1);
		run("Paste");
		selectWindow("pixelTouches");
		getRawStatistics(count, mean, min, max, std);
		nBins = 1 + max - min;
		getHistogram(null, counts, nBins, min, max);
		counts = Array.sort(counts);
		counts = Array.reverse(counts);
		GrayCount = 0;
		for (k=0; k<nBins; k++) {
			if (counts[k]!=0) GrayCount = GrayCount+1;
			else k = nBins;
		}
		ProxCount = GrayCount - 2; /* Correct for background and original object */
		setResult("Touch.N.", i, ProxCount);
		close("pixelTouches");
	}
	closeImageByTitle("Labeled");
	print("-----\n\n");
	print("Touching Neighbor Count macro");
	print("Image used for count: " + TitleOriginalBinaryImage);
	print("Run time = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	restoreSettings();
	setBatchMode("exit & display"); /* exit batch mode */
	/*
		( 8(|)	( 8(|)	All ASC Functions	@@@@@:-)	@@@@@:-)
	*/
	function checkForPlugin(pluginName) {
		/* v161102 changed to true-false
			v180831 some cleanup
			v210429 Expandable array version
			v220510 Looks for both class and jar if no extension is given
			v220818 Mystery issue fixed, no longer requires restoreExit	*/
		pluginCheck = false;
		if (getDirectory("plugins") == "") print("Failure to find any plugins!");
		else {
			pluginDir = getDirectory("plugins");
			if (lastIndexOf(pluginName,".")==pluginName.length-1) pluginName = substring(pluginName,0,pluginName.length-1);
			pExts = newArray(".jar",".class");
			knownExt = false;
			for (j=0; j<lengthOf(pExts); j++) if(endsWith(pluginName,pExts[j])) knownExt = true;
			pluginNameO = pluginName;
			for (j=0; j<lengthOf(pExts) && !pluginCheck; j++){
				if (!knownExt) pluginName = pluginName + pExts[j];
				if (File.exists(pluginDir + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + "found in: "  + pluginDir);
				}
				else {
					pluginList = getFileList(pluginDir);
					subFolderList = newArray;
					for (i=0,subFolderCount=0; i<lengthOf(pluginList); i++) {
						if (endsWith(pluginList[i], "/")) {
							subFolderList[subFolderCount] = pluginList[i];
							subFolderCount++;
						}
					}
					for (i=0; i<lengthOf(subFolderList); i++) {
						if (File.exists(pluginDir + subFolderList[i] +  "\\" + pluginName)) {
							pluginCheck = true;
							showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
							i = lengthOf(subFolderList);
						}
					}
				}
			}
		}
		return pluginCheck;
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002 reselects original image at end if open
		   v200925 uses "while" instead of "if" so that it can also remove duplicates
		*/
		oIID = getImageID();
        while (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function restoreExit(message){ /* v220316
		NOTE: REQUIRES previous run of saveSettings	*/
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		call("java.lang.System.gc");
		if (message!="") exit(message);
		else exit;
	}