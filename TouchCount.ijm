/*	ImageJ Macro to count the number of unique objects touching the each object
	Uniqueness is guaranteed by G. Landini's binary labeling plugin (part of "Morphology" package
	Uses histogram macro functions so that no additional particle analysis is required.
	Assumes that touching objects have been separated by one pixel.
	5/31/2016 10:50 AM Peter J. Lee (NHMFL) 
*/
	start = getTime(); // start timer after last requester for debugging
	setBatchMode(true);
	saveSettings(); /* To restore settings at the end */
		
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
	if (((getPixel(0, 0))+(getPixel(0, 1))+(getPixel(1, 0))+(getPixel(1, 1))) != 0 ) 
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
	if (isOpen("Labeled")) {
	selectWindow("Labeled");
	run("Close");
	}
	print("-----\n\n");
	print("Touching Neighbor Count macro");
	print("Image used for count: " + TitleOriginalBinaryImage);
	print("Run time = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	restoreSettings();
	setBatchMode("exit & display"); /* exit batch mode */
	
	function restoreExit(message){ // clean up before aborting macro then exit
		restoreSettings(); //clean up before exiting
		setBatchMode("exit & display"); // not sure if this does anything useful if exiting gracefully but otherwise harmless
		exit(message);
	}