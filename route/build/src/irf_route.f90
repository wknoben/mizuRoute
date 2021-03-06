module irf_route_module

!numeric type
USE nrtype
! data type
USE dataTypes,          only : STRFLX         ! fluxes in each reach
USE dataTypes,          only : RCHTOPO        ! Network topology
! global parameters
USE public_var,         only : realMissing    ! missing value for real number
USE public_var,         only : integerMissing ! missing value for integer number
USE globalData,         only : nThreads          ! number of threads used for openMP

! privary
implicit none
private

public::irf_route

contains

 ! *********************************************************************
 ! subroutine: perform network UH routing
 ! *********************************************************************
 subroutine irf_route(iEns,          &  ! input: index of runoff ensemble to be processed
                      river_basin,   &  ! input: river basin information (mainstem, tributary outlet etc.)
                      ixDesire,      &  ! input: reachID to be checked by on-screen pringing
                      NETOPO_in,     &  ! input: reach topology data structure
                      RCHFLX_out,    &  ! inout: reach flux data structure
                      ierr, message, &  ! output: error control
                      ixSubRch)         ! optional input: subset of reach indices to be processed

 ! global routing data
 USE dataTypes,  only : subbasin_omp   ! mainstem+tributary data structures

 implicit none
 ! Input
 integer(i4b),       intent(in)                  :: iEns                ! runoff ensemble to be routed
 type(subbasin_omp), intent(in),    allocatable  :: river_basin(:)      ! river basin information (mainstem, tributary outlet etc.)
 integer(i4b),       intent(in)                  :: ixDesire            ! index of the reach for verbose output ! Output
 type(RCHTOPO),      intent(in),    allocatable  :: NETOPO_in(:)        ! River Network topology
 ! inout
 TYPE(STRFLX),       intent(inout), allocatable  :: RCHFLX_out(:,:)     ! Reach fluxes (ensembles, space [reaches]) for decomposed domains
 ! output variables
 integer(i4b),       intent(out)                 :: ierr                ! error code
 character(*),       intent(out)                 :: message             ! error message
 ! input (optional)
 integer(i4b),       intent(in), optional        :: ixSubRch(:)         ! subset of reach indices to be processed
 ! Local variables
 character(len=strLen)                           :: cmessage            ! error message from subroutine
 logical(lgt),                      allocatable  :: doRoute(:)          ! logical to indicate which reaches are processed
 integer(i4b)                                    :: nOrder              ! number of stream order
 integer(i4b)                                    :: nTrib               ! number of tributary basins
 integer(i4b)                                    :: nSeg                ! number of reaches in the network
 integer(i4b)                                    :: iSeg, jSeg          ! loop indices - reach
 integer(i4b)                                    :: iTrib               ! loop indices - branch
 integer(i4b)                                    :: ix                  ! loop indices stream order
 ! variables needed for timing
 integer*8                                       :: cr                  ! rate
 integer*8                                       :: startTime,endTime   ! date/time for the start and end of the initialization
 real(dp)                                        :: elapsedTime         ! elapsed time for the process
 !integer(i4b)                                    :: omp_get_thread_num
 !integer(i4b), allocatable                       :: ixThread(:)         ! thread id
 !integer*8,    allocatable                       :: openMPend(:)        ! time for the start of the parallelization section
 !integer*8,    allocatable                       :: timeTribStart(:)    ! time Tributaries start
 !real(dp),     allocatable                       :: timeTrib(:)         ! time spent on each Tributary

 ! initialize error control
 ierr=0; message='irf_route/'
 call system_clock(count_rate=cr)

 ! number of reach check
 if (size(NETOPO_in)/=size(RCHFLX_out(iens,:))) then
  ierr=20; message=trim(message)//'sizes of NETOPO and RCHFLX mismatch'; return
 endif

 nSeg = size(NETOPO_in)

 allocate(doRoute(nSeg), stat=ierr)

 ! Initialize CHEC_IRF to False.
 RCHFLX_out(iEns,:)%CHECK_IRF=.False.

 if (present(ixSubRch))then
  doRoute(:)=.false.
  doRoute(ixSubRch) = .true. ! only subset of reaches are on
 else
  doRoute(:)=.true. ! every reach is on
 endif

 nOrder = size(river_basin)

 call system_clock(startTime)

 do ix = 1,nOrder

   nTrib=size(river_basin(ix)%branch)

!  allocate(ixThread(nTrib), openMPend(nTrib), timeTrib(nTrib), timeTribStart(nTrib), stat=ierr)
!  if(ierr/=0)then; message=trim(message)//trim(cmessage)//': unable to allocate space for Trib timing'; return; endif
!  timeTrib(:) = realMissing
!  ixThread(:) = integerMissing

  ! 1. Route tributary reaches (parallel)
!$OMP PARALLEL DO schedule(dynamic,1)                   &
!$OMP          private(jSeg, iSeg)                      & ! private for a given thread
!$OMP          private(ierr, cmessage)                  & ! private for a given thread
!$OMP          shared(river_basin)                      & ! data structure shared
!$OMP          shared(doRoute)                          & ! data array shared
!$OMP          shared(NETOPO_in)                        & ! data structure shared
!$OMP          shared(RCHFLX_out)                       & ! data structure shared
!$OMP          shared(ix, iEns, ixDesire)               & ! indices shared
!$OMP          firstprivate(nTrib)
!!$OMP          shared(openMPend, nThreads)              & ! timing variables shared
!!$OMP          shared(timeTribStart)                    & ! timing variables shared
!!$OMP          shared(timeTrib)                         & ! timing variables shared
!!$OMP          shared(ixThread)                         & ! thread id array shared
   trib:do iTrib = 1,nTrib
!!$    ixThread(iTrib) = omp_get_thread_num()
!    call system_clock(timeTribStart(iTrib))
     seg:do iSeg=1,river_basin(ix)%branch(iTrib)%nRch
       jSeg = river_basin(ix)%branch(iTrib)%segIndex(iSeg)
       if (.not. doRoute(jSeg)) cycle
       call segment_irf(iEns, jSeg, ixDesire, NETOPO_IN, RCHFLX_out, ierr, cmessage)
!      if(ierr/=0)then; ixmessage(iTrib)=trim(message)//trim(cmessage); exit; endif
     end do seg
!    call system_clock(openMPend(iTrib))
!    timeTrib(iTrib) = real(openMPend(iTrib)-timeTribStart(iTrib), kind(dp))
   end do trib
!$OMP END PARALLEL DO

!  write(*,'(a)') 'iTrib nSeg ixThread nThreads StartTime EndTime'
!  do iTrib=1,nTrib
!    write(*,'(4(i5,1x),2(I20,1x))') iTrib, river_basin(iOut)%branch(iTrib)%nRch, ixThread(iTrib), nThreads, timeTribStart(iTrib), openMPend(iTrib)
!  enddo
!  deallocate(ixThread, openMPend, timeTrib, timeTribStart, stat=ierr)
!  if(ierr/=0)then; message=trim(message)//trim(cmessage)//': unable to deallocate space for Trib timing'; return; endif

 end do ! basin loop

 call system_clock(endTime)
 elapsedTime = real(endTime-startTime, kind(dp))/real(cr)
 !write(*,"(A,1PG15.7,A)") '  elapsed-time [routing/irf] = ', elapsedTime, ' s'

 end subroutine irf_route


 ! *********************************************************************
 ! subroutine: perform one segment route UH routing
 ! *********************************************************************
 subroutine segment_irf(&
                        ! input
                        iEns,       &    ! input: index of runoff ensemble to be processed
                        segIndex,   &    ! input: index of runoff ensemble to be processed
                        ixDesire,   &    ! input: reachID to be checked by on-screen pringing
                        NETOPO_in,  &    ! input: reach topology data structure
                        ! inout
                        RCHFLX_out, &    ! inout: reach flux data structure
                        ! output
                        ierr, message)   ! output: error control

 implicit none
 ! Input
 INTEGER(I4B), intent(IN)                 :: iEns           ! runoff ensemble to be routed
 INTEGER(I4B), intent(IN)                 :: segIndex       ! segment where routing is performed
 INTEGER(I4B), intent(IN)                 :: ixDesire       ! index of the reach for verbose output
 type(RCHTOPO),intent(in),    allocatable :: NETOPO_in(:)   ! River Network topology
 ! inout
 TYPE(STRFLX), intent(inout), allocatable :: RCHFLX_out(:,:)   ! Reach fluxes (ensembles, space [reaches]) for decomposed domains
 ! Output
 integer(i4b), intent(out)                :: ierr           ! error code
 character(*), intent(out)                :: message        ! error message
 ! Local variables to
 type(STRFLX), allocatable                :: uprflux(:)     ! upstream Reach fluxes
 INTEGER(I4B)                             :: nUps           ! number of upstream segment
 INTEGER(I4B)                             :: iUps           ! upstream reach index
 INTEGER(I4B)                             :: iRch_ups       ! index of upstream reach in NETOPO
 INTEGER(I4B)                             :: ntdh           ! number of time steps in IRF
 character(len=strLen)                    :: cmessage       ! error message from subroutine

 ! initialize error control
 ierr=0; message='segment_irf/'

 ! route streamflow through the river network
  if (.not.allocated(RCHFLX_out(iens,segIndex)%QFUTURE_IRF))then

   ntdh = size(NETOPO_in(segIndex)%UH)

   allocate(RCHFLX_out(iens,segIndex)%QFUTURE_IRF(ntdh), stat=ierr, errmsg=cmessage)
   if(ierr/=0)then; message=trim(message)//trim(cmessage)//': RCHFLX_out(iens,segIndex)%QFUTURE_IRF'; return; endif

   RCHFLX_out(iens,segIndex)%QFUTURE_IRF(:) = 0._dp

  end if

  ! identify number of upstream segments of the reach being processed
  nUps = size(NETOPO_in(segIndex)%UREACHI)

  allocate(uprflux(nUps), stat=ierr, errmsg=cmessage)
  if(ierr/=0)then; message=trim(message)//trim(cmessage)//': uprflux'; return; endif

  if (nUps>0) then
    do iUps = 1,nUps
      iRch_ups = NETOPO_in(segIndex)%UREACHI(iUps)      !  index of upstream of segIndex-th reach
      uprflux(iUps) = RCHFLX_out(iens,iRch_ups)
    end do
  endif

  ! perform river network UH routing
  call conv_upsbas_qr(NETOPO_in(segIndex)%UH,    &    ! input: reach unit hydrograph
                      uprflux,                   &    ! input: upstream reach fluxes
                      RCHFLX_out(iens,segIndex), &    ! inout: updated fluxes at reach
                      ierr, message)                  ! output: error control
  if(ierr/=0)then; message=trim(message)//trim(cmessage); return; endif

  ! Check True since now this reach now routed
  RCHFLX_out(iEns,segIndex)%CHECK_IRF=.True.

  ! check
  if(NETOPO_in(segIndex)%REACHIX == ixDesire)then
   print*, 'RCHFLX_out(iens,segIndex)%BASIN_QR(1),RCHFLX_out(iens,segIndex)%REACH_Q_IRF = ', &
            RCHFLX_out(iens,segIndex)%BASIN_QR(1),RCHFLX_out(iens,segIndex)%REACH_Q_IRF
  endif

 end subroutine segment_irf


 ! *********************************************************************
 ! subroutine: Compute delayed runoff from the upstream segments
 ! *********************************************************************
 subroutine conv_upsbas_qr(reach_uh,   &    ! input: reach unit hydrograph
                           rflux_ups,  &    ! input: upstream reach fluxes
                           rflux,      &    ! input: input flux at reach
                           ierr, message)   ! output: error control
 ! ----------------------------------------------------------------------------------------
 ! Details: Convolute runoff volume of upstream at one reach at one time step
 ! ----------------------------------------------------------------------------------------

 implicit none
 ! Input
 real(dp),     intent(in)               :: reach_uh(:)  ! reach unit hydrograph
 type(STRFLX), intent(in)               :: rflux_ups(:) ! upstream Reach fluxes
 ! inout
 type(STRFLX), intent(inout)            :: rflux        ! current Reach fluxes
 ! Output
 integer(i4b), intent(out)              :: ierr         ! error code
 character(*), intent(out)              :: message      ! error message
 ! Local variables to
 real(dp)                               :: q_upstream   ! total discharge at top of the reach being processed
 INTEGER(I4B)                           :: ntdh         ! number of UH data
 INTEGER(I4B)                           :: itdh         ! index of UH data (i.e.,future time step)
 INTEGER(I4B)                           :: nUps         ! number of all upstream segment
 INTEGER(I4B)                           :: iUps         ! loop indices for u/s reaches

 ! initialize error control
 ierr=0; message='conv_upsbas_qr/'

 ! identify number of upstream segments of the reach being processed
 nUps = size(rflux_ups)

 ! Find out total q at top of a segment
 q_upstream = 0.0_dp
 if(nUps>0)then
   do iUps = 1,nUps
     q_upstream = q_upstream + rflux_ups(iUps)%REACH_Q_IRF
   end do
 endif

 ! place a fraction of runoff in future time steps
 ntdh = size(reach_uh) ! identify the number of future time steps of UH for a given segment
 do itdh=1,ntdh
   rflux%QFUTURE_IRF(itdh) = rflux%QFUTURE_IRF(itdh) &
                             + reach_uh(itdh)*q_upstream
 enddo

 ! Add local routed flow
 rflux%REACH_Q_IRF = rflux%QFUTURE_IRF(1) + rflux%BASIN_QR(1)

 ! move array back   use eoshift
 !rflux%QFUTURE_IRF=eoshift(rflux%QFUTURE_IRF,shift=1)

 do itdh=2,ntdh
  rflux%QFUTURE_IRF(itdh-1) = rflux%QFUTURE_IRF(itdh)
 enddo

 rflux%QFUTURE_IRF(ntdh) = 0._dp

 end subroutine conv_upsbas_qr

end module irf_route_module

