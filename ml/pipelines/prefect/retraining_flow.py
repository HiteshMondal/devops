from prefect import flow, task
import subprocess

@task
def check_drift() -> bool:
    # Placeholder: real logic reads from evidently/whylabs reports
    print("Checking for data drift...")
    return False  # True triggers retraining

@task
def retrain():
    print("Retraining model...")
    subprocess.run(["python", "ml/pipelines/metaflow/training_flow.py", "run"], check=True)

@flow(name="retraining-flow")
def retraining_flow():
    drift_detected = check_drift()
    if drift_detected:
        retrain()
    else:
        print("No drift detected. Skipping retraining.")

if __name__ == "__main__":
    retraining_flow()