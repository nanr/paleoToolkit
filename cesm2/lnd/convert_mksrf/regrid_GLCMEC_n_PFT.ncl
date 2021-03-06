;
; Regrid Glacier and PFT datasets to half degree
;

function NormalizeTo100_ ( array[*][*][*]:numeric )
;
; Normalize the incoming array to 100
;
local temp, diff, i, j, sumarray;
begin
   temp = array;
   do i = 0, dimsizes(array(0,:,0))-1
   do j = 0, dimsizes(array(0,0,:))-1
       sumarray = sum(array(:,i,j));
       if ( sumarray .gt. 0.0d00 )then
          temp(:,i,j) = temp(:,i,j)*100.0d00 / sumarray
          diff = sum(temp(:,i,j)) - 100.0d00
          if ( abs(diff) .gt. 0.0d00 )then
             temp(0,i,j) = temp(0,i,j) - diff
             diff = sum(temp(:,i,j)) - 100.0d00
             if ( abs(diff) .gt. 1.d-13 )then
                print( "PCT PFT does not sum to 100.0: "+sum(temp(:,i,j)) );
                print( "Difference: "+diff );
                print( temp(:,i,j) );
                exit();
             end if
          end if
       end if
   end do
   end do
   return( temp );
end

procedure duplicate_file4newgrid ( infilename:string, outfilename:string, ncin:file, ncout:file, ncgrd:file )
;
; Duplicate the input file on the output file with a new grid
;
local nlat, nlon, dsizes, ndims, dimnames, is_unlim, i, j, vars, vardims, outlat, outlon, outmsk
begin
   print( "Work on "+outfilename );
   ;
   ; Define Dimensions
   ;
   print( "Define dims" );
   outlat = (/ ncgrd->LAT /);
   outlon = (/ ncgrd->LON /);
   nlat = dimsizes(outlat);
   nlon = dimsizes(outlon)
   dsizes = getfiledimsizes( ncin );
   ndims  = dimsizes(dsizes);
   ; Get dimension names
   dimnames = getfiledims( ncin );
   ;
   is_unlim = new( (/ ndims /), "logical" );
   is_unlim = False;
   do i = 0, ndims-1
      if ( dimnames(i) .eq. "time" )then
         is_unlim(i) = True;
      else
         if ( dimnames(i) .eq. "lat" )then
            dsizes(i) = nlat;
         else
            if ( dimnames(i) .eq. "lon" )then
               dsizes(i) = nlon;
            else
               if ( dimnames(i) .eq. "ncl_scalar" )then
                  dimnames(i) = "scalar";
               end if
            end if
         end if
      end if
   end do
   filedimdef( ncout, dimnames, dsizes, is_unlim );
   ;
   ; Define Variables
   ;
   print( "Define vars" );
   vars = getfilevarnames( ncin );
   do i = 0, dimsizes(vars)-1
      print( "var: "+vars(i) );
      vardims = getfilevardims( ncin, vars(i) );
      do j = 0, dimsizes(vardims)-1
         if ( vardims(j) .eq. "ncl_scalar" )then
            vardims(j) = "scalar";
         end if
      end do
      if ( (typeof(ncin->$vars(i)$) .eq. "short") .or. (typeof(ncin->$vars(i)$) .eq. "integer") )then
         filevardef ( ncout, (/ vars(i) /), "float",  vardims );
      else
         filevardef ( ncout, (/ vars(i) /), (/ typeof(ncin->$vars(i)$) /),  vardims );
      end if
      filevarattdef ( ncout, (/ vars(i) /), ncin->$vars(i)$ );
      delete( vardims );
   end do
   ;
   ; Global attributes
   ;
   print( "set global attributes" );
   fileattdef( ncout, ncin );
   date = systemfunc( "date" );
   desc = "Regrid using regrid_GLCMEC_n_PFT.ncl from: "+infilename;
   history = ""
   if ( isvar(ncin@history) )then
      history = ncin@history;
   end if
   ncout@history = date + " : " + desc + str_get_nl() + history;
   ;
   ; Set static variables
   ;
   print( "set static vars" );
   outmsk = (/ ncgrd->LANDMASK /);
   outlatixy = (/ ncgrd->LATIXY /);
   outlongxy = (/ ncgrd->LONGXY /);

   ncout->LAT      = outlat;
   ncout->LON      = outlon;
   ncout->LATIXY   = outlatixy;
   ncout->LONGXY   = outlongxy;
   ncout->LANDMASK = outmsk;
   ;
   ; Go through variables and copy or regrid
   ;
   print( "Go through variables and copy or regrid" );
   do i = 0, dimsizes(vars)-1
      vardims = getfilevardims( ncin, vars(i) );
      ; Regrid variables with lat or lon dimensions
      if ( (any(vardims .eq. "lat") ) .or. (any(vardims .eq. "lon")) )then
         if ( (str_upper(vars(i)) .ne. "LAT") .and. (str_upper(vars(i)) .ne. "LON") .and. (vars(i) .ne. "LANDMASK") .and. (vars(i) .ne. "LATIXY") .and. (vars(i) .ne. "LONGXY") )then
            print( "Regrid "+vars(i) );
            tmp = (/ ncin->$vars(i)$ /)
            if ( dimsizes(ncin->LON) .ge. 7200 )then
               tmp2 = area_hi2lores ( ncin->LON, ncin->LAT, tmp, False, 1.0d00, outlon, outlat, False );
            else
               tmp2 = area_conserve_remap ( ncin->LON, ncin->LAT, tmp, outlon, outlat, False );
            end if
            delete( tmp  );
            print( "after regrid" );
            if ( vars(i) .eq. "PCT_NAT_PFT" )then
               print( "Make sure PCT_NAT_PFT still sums to 100.0" );
               tmp2 = NormalizeTo100_( tmp2 );
            end if
            ncout->$vars(i)$ = tmp2;
            delete( tmp2 );
         end if
      ; Otherwise just copy
      else
         print( "Copy "+vars(i) );
         ncout->$vars(i)$ = (/ ncin->$vars(i)$ /);
      end if
      delete( vardims )
   end do
end

begin
   if ( ("$DIN_LOC_ROOT" .eq. "") .or. (systemfunc("test -d $DIN_LOC_ROOT; echo $?" ) .ne. 0) )then
      print( "Env variable: DIN_LOC_ROOT not set or not set to a directory" );
      exit();
   end if
   ;
   ; Set Input files and open them
   ;
   glacierfile = "$DIN_LOC_ROOT/lnd/clm2/rawdata/mksrf_glacier_3x3min_simyr2000.c120926.nc"
   pftfile     = "$DIN_LOC_ROOT/lnd/clm2/rawdata/pftcftdynharv.0.25x0.25.LUH2.simyrPtVg.c181106/mksrf_landuse_potvegclm50_LUH2.c181106.nc"
   lakfile     = "$DIN_LOC_ROOT/lnd/clm2/rawdata/mksrf_LakePnDepth_3x3min_simyr2004_csplk_c151015.nc"
   gridfile    = "$DIN_LOC_ROOT//lnd/clm2/rawdata/mksrf_lanwat.050425.nc"

   print( "Open: "+glacierfile );
   ncglc = addfile( glacierfile, "r" );
   print( "Open: "+pftfile );
   ncpft = addfile( pftfile, "r" );
   print( "Open: "+lakfile );
   nclak = addfile( lakfile, "r" );
   print( "Open: "+gridfile );
   ncgrd = addfile( gridfile, "r" );
   ;
   ; Open output files for half degree versions
   ;
   sdate    = systemfunc( "date +%y%m%d" );

   outglacierfile = "mksrf_glacier_0.5x0.5_simyr2000.c"+sdate+".nc";
   outpftfile     = "mksrf_landuse_0.5x0.5_potvegclm50_LUH2.c"+sdate+".nc";
   outlakfile     = "mksrf_LakePnDepth_0.5x0.5_simyr2004_csp1k.c"+sdate+".nc";

   print( "Open : "+outglacierfile );
   if ( systemfunc("test -f "+outglacierfile+"; echo $?" ) .eq. 0 )then
      system( "/bin/rm "+outglacierfile );
   end if
   nco_glc = addfile( outglacierfile, "c" );
   print( "Open : "+outpftfile );
   if ( systemfunc("test -f "+outpftfile+"; echo $?" ) .eq. 0 )then
      system( "/bin/rm "+outpftfile );
   end if
   nco_pft = addfile( outpftfile, "c" );
   print( "Open : "+outlakfile );
   if ( systemfunc("test -f "+outlakfile+"; echo $?" ) .eq. 0 )then
      system( "/bin/rm "+outlakfile );
   end if
   nco_lak = addfile( outlakfile, "c" );
   ;
   ; Duplicate the file on the new grid
   ;
   duplicate_file4newgrid ( glacierfile, outglacierfile, ncglc, nco_glc, ncgrd );
   delete( nco_glc );
   delete( ncglc );
   duplicate_file4newgrid ( pftfile,     outpftfile,     ncpft, nco_pft, ncgrd );
   delete( nco_pft );
   delete( ncpft );
   duplicate_file4newgrid ( lakfile,     outlakfile,     nclak, nco_lak, ncgrd );
   delete( nco_lak );
   delete( nclak );
   delete( ncgrd );

   print( "" );
   print( "Successfully regrid files" );
end
