!---------------------------------------------------------------------------------------------------
!
!PROGRAM: driver_irfs.f90
!> @author Christopher Gust
!> @version 1.0
!> @date 11-17-16
!
!DESCRIPTION:
!> Read in parameters and compute irfs to risk premium or MEI shock.
!_________________________________________________________________________________________________________
program driver_irfs
  use utils, only: read_matrix, write_matrix
  use class_model, only: model
  implicit none
  include 'mpif.h'

  type(model) :: m
  logical, parameter :: parallelswitch = .true.
  integer, parameter :: neulererrors = 18
  integer :: i,captirf,nsim,shockindex,dsetswitch
  logical :: zlbswitch,convergence
  double precision, allocatable :: endogirf(:,:)
  double precision, allocatable :: linirf(:,:)
  double precision, allocatable :: euler_errors(:,:)
  integer :: rank
  integer :: nproc
  integer :: mpierror
  character(len=150) :: arg,param_type
  character (len=250) :: filename

  if (parallelswitch .eq. .true.) then
     call MPI_init(mpierror)
     call MPI_Comm_size(MPI_COMM_WORLD,nproc,mpierror)
     call MPI_Comm_rank(MPI_COMM_WORLD,rank,mpierror)
     write(*,*) 'Hello from processor ', rank, 'I am 1 of ', nproc ,' processes running'
  else
     rank = 0
     write(*,*) 'You are running the serial version of the code.'
  end if

  nsim = 5000
  captirf = 20
  shockindex = 1  !1=risk premium; 2=MEI; 
  dsetswitch = 0  !0=mean parameters; otherwise median
  
  do i = 1, command_argument_count()
     call get_command_argument(i, arg)
     select case(arg)
     case ('--nsim', '-n')
        call get_command_argument(i+1, arg)
        read(arg, '(i)') nsim
     case('--capt', '-c')
        call get_command_argument(i+1, arg)
        read(arg, '(i)') captirf
     case('--shockindex', '-s')
        call get_command_argument(i+1, arg)
        read(arg, '(i)') shockindex
     case('--dset','-d')
        call get_command_argument(i+1,arg)
        read(arg, '(i)') dsetswitch
     end select
  end do
  
  if ((shockindex .lt. 1) .or. (shockindex .gt. 2)) stop 'shockindex can only be 1 or 2 (driverirf)'
  
  !iniitialize solution details
  zlbswitch = .true.
  m = model(zlbswitch)  
  if (rank .eq. 0) then
     call m%describe()
     write(*,*) 'capt = ', captirf
     write(*,*) 'number of draws for MC integration = ', nsim
     if (shockindex .eq. 1) write(*,*) 'IRF to Risk Premium Shock'
     if (shockindex .eq. 2) write(*,*) 'IRF to MEI Shock'
     write(*,*) '----------------------------'
  end if

  !allocate matrices for IRFs
  allocate(endogirf(m%solution%poly%nvars+m%solution%poly%nexog+2,captirf))
  allocate(linirf(m%solution%poly%nvars+m%solution%poly%nexog+2,captirf))
  allocate(euler_errors(2*neulererrors,captirf))
  
  !get parameters from disk
  if (dsetswitch .eq. 0) then
     param_type = 'mean'
  else
     param_type = 'median'
  end if
  filename = '/msu/scratch3/m1cjg01/aer_revision_ed/final_code/final-final/' // trim(param_type) //  '.txt'
  call read_matrix(filename,m%solution%poly%nparams,1,m%params)

  !solve model
  if (parallelswitch .eq. .true.) then
     convergence = m%solve_parallel(m%params,nproc,rank)
  else
     convergence = m%solve(m%params)
  end if

  if (convergence .eq. .false.) then  !if no solution, report this back to disk
     if (rank .eq. 0) write(*,*) 'Failed to converge (driverirf)'     
  else  !if computed solution, simulate and send irf data to disk
     if (rank .eq. 0) then
        write(*,*) 'Successfully solved model (driverirf). Computing IRFs.' 
        call m%simulate_modelirfs(captirf,nsim,shockindex,endogirf,linirf,euler_errors,neulererrors)
        !send irfs to disk
        if (zlbswitch .eq. .true.) then
           write(filename,"(A,I0,A)") './irf-results/nonlinearirf_' // trim(param_type) // '_', shockindex , '.txt'
        else
           write(filename,"(A,I0,A)") './irf-results/nonlinearirf_unc_' // trim(param_type) // '_', shockindex , '.txt'
        end if
        call write_matrix(filename,m%solution%poly%nvars+m%solution%poly%nexog+2,captirf,endogirf)    
        write(filename,"(A,I0,A)") './irf-results/linearirf_' // trim(param_type) // '_', shockindex , '.txt'
        call write_matrix(filename,m%solution%poly%nvars+m%solution%poly%nexog+2,captirf,linirf) 
        write(filename,"(A,I0,A)") './irf-results/eulers_' // trim(param_type) // '_', shockindex, '.txt'
        call write_matrix(filename,2*neulererrors,captirf,euler_errors)    
     end if
  end if
 
  deallocate(endogirf,linirf,euler_errors)
  call m%cleanup()

  if (parallelswitch .eq. .true.) then
     call MPI_finalize(mpierror)
  end if
   
end program driver_irfs
