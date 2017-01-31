# asc-ImageJ-TouchCount-and-Proximity
<p>These ImageJ macros (<a href="https://github.com/peterjlee/asc-ImageJ-TouchCount-and-Proximity" Title = "Applied Superconductivity Center Touch Count and Proximity Macro Directory" >link</a>) count the number of objects that are touching each other<a href="http://fs.magnet.fsu.edu/~lee/asc/ImageJUtilities/ASC-Macros/LayerThickness/Minimum%20wall%20thickness%20macro_060816.pdf"></a>. It assumes that all objects have been previously separated by using the watershed tool (i.e.  &quot;touching&quot; objects will be separated by  1 pixel). The proximity+touchcount version also counts the number of objects within successive increases of 1 pixel up to 10 pixels and converts these separations to the scaled unit if there is one (if just pixels are preferred just remove the scale prior to running the macro).</p><p><img src="http://fs.magnet.fsu.edu/~lee/asc/ImageJUtilities/IA_Images/ProximityandTouchCount_Example_mplPlasma_anim573x190.gif" alt="Touch count of each object." width="572" height="190" /></p>